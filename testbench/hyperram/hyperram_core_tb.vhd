LIBRARY ieee  ;
    USE ieee.NUMERIC_STD.all  ;
    USE ieee.std_logic_1164.all  ;

library vunit_lib;
context vunit_lib.vunit_context;

    use work.hyperram_pkg.all;

-- hyperram_core through its native interface at 200 MHz, with models of the DDIO pins, the PLL
-- phase shift of the read clock and the HyperRAM (both dies), as hyperram_axi_tb has them. A
-- client answers every write request from its words (a registered answer) and takes every read
-- word; a shadow of the memory gives the read words' expected values (only bytes written are
-- checked).
--   calibrates_on_both_dies           the calibration passes, the status says so
--   writes_and_reads_back             transactions of 1, 3, 64 and 512 words with random byte
--                                     strobes, at the end of die 0 and the start of die 1
--   a_read_that_times_out_is_padded   RWDS cut during a read: its words padded with zeros, a
--                                     timeout counted, the next read right
--   tckd_ns      CK to DQ/RWDS delay of the memory model
--   lo_lags      pairing of the input DDIO halves, see the input register model
--   phase_steps  0: the PLL's phase is absolute (8 steps of 250 ps); > 0: relative, as the
--                Agilex 3 I/O PLL's - each change of the shift value by -1 moves the read clock
--                a step (a period / phase_steps) earlier, acknowledged on phase_shift_done
--                after a write's latency; any other change is an error here
--   ignored_steps  relative: the first steps acknowledged but not made (the Agilex 3 PLL right
--                after configuration) - the calibration's check of its step must catch it
entity hyperram_core_tb is
  generic (runner_cfg : string; tckd_ns : real := 3.0; lo_lags : boolean := true;
           phase_steps : natural := 0; ignored_steps : natural := 0);
end;

architecture vunit_simulation of hyperram_core_tb is

    constant hr_period  : time := 5 ns;
    constant phase_step : time := 250 ps;
    constant model_bits : natural := 14;            -- 16 K words a die in the model

    signal hr_clock   : std_logic := '0';
    signal ck_clock   : std_logic := '0';
    signal read_clock : std_logic := '0';
    signal read_delay : time := 0 ns;
    signal reset      : boolean := true;

    -- the native interface
    signal command_valid, command_ready, command_write : boolean := false;
    signal command_address : unsigned(24 downto 0) := (others => '0');
    signal command_words   : natural range 1 to 512 := 1;
    signal write_request   : boolean;
    signal write_word      : std_logic_vector(15 downto 0) := (others => '0');
    signal write_strobe    : std_logic_vector(1 downto 0) := (others => '0');
    signal read_valid      : boolean;
    signal read_word       : std_logic_vector(15 downto 0);
    signal done            : boolean;
    signal in_reset        : boolean;

    signal calibration_done, calibration_passed : boolean;
    signal status        : std_logic_vector(31 downto 0);
    signal read_timeouts : unsigned(15 downto 0);
    signal core_debug    : std_logic_vector(23 downto 0);
    signal phase_shift   : pll_phase_shift_record;
    signal phase_shift_done : std_logic := '0';
    constant write_latency  : time := 3 us;       -- of a phase write through the calibration IP
    signal fpga_out      : hyperram_ddr_fpga_out_record;
    signal fpga_in       : hyperram_ddr_fpga_in_record;
    signal fpga_in_model : hyperram_ddr_fpga_in_record;
    signal rwds_cut      : boolean := false;   -- RWDS read as low: a read times out

    -- pins
    signal ck, cs_n, reset_n : std_logic := '0';
    signal dq   : std_logic_vector(7 downto 0);
    signal rwds : std_logic;
    signal dq_out_pin  : std_logic_vector(7 downto 0) := (others => '0');
    signal rwds_out_pin, dq_oe_pin, rwds_oe_pin : std_logic := '0';

    -- the client: the words of the write under way, the read words taken
    type word_array is array (natural range <>) of std_logic_vector(15 downto 0);
    type strobe_array is array (natural range <>) of std_logic_vector(1 downto 0);
    signal w_words    : word_array(0 to 511);
    signal w_strobes  : strobe_array(0 to 511);
    signal w_index    : natural := 0;
    signal r_words    : word_array(0 to 511);
    signal r_count    : natural := 0;
    signal w_clear, r_clear : boolean := false;   -- the main process's: the client's counts to 0

begin

    hr_clock   <= not hr_clock after hr_period/2;
    ck_clock   <= transport hr_clock after 3*hr_period/4;
    read_clock <= transport hr_clock after read_delay;
    reset      <= false after 100 ns;

    -- PLL dynamic phase shift: SHIFT is taken when SHIFT_ENA is high
    absolute_pll : if phase_steps = 0 generate
        pll_model : process(phase_shift.shift_enable)
        begin
            if phase_shift.shift_enable = '1' and phase_shift.shift_select = "01000" then
                read_delay <= to_integer(unsigned(phase_shift.shift)) * phase_step;
            end if;
        end process;
    end generate;

    relative_pll : if phase_steps > 0 generate
        pll_model : process
            variable mux   : unsigned(2 downto 0) := "000";
            variable steps_down : natural := 0;
            variable requests   : natural := 0;
        begin
            wait until rising_edge(phase_shift.shift_enable);
            if phase_shift.shift_select = "01000" and unsigned(phase_shift.shift) /= mux then
                check(unsigned(phase_shift.shift) = mux - 1, "a relative phase changes only by -1");
                mux := unsigned(phase_shift.shift);
                requests := requests + 1;
                if requests > ignored_steps then
                    steps_down := (steps_down + 1) mod phase_steps;
                end if;
                wait for write_latency;
                -- a step earlier: the read clock's delay one step less, round a period
                read_delay <= ((phase_steps - steps_down) mod phase_steps) * (hr_period / phase_steps);
                phase_shift_done <= not phase_shift_done;
            end if;
        end process;
    end generate;

------------------------------------------------------------------------
    -- output registers: DDIO resync, both halves taken on the rising edge, hi driven in the
    -- first half of the cycle and lo in the second
    ddio_out : process(hr_clock)
        variable dq_lo_hold   : std_logic_vector(7 downto 0);
        variable rwds_lo_hold : std_logic;
    begin
        if rising_edge(hr_clock) then
            dq_out_pin   <= fpga_out.dq_hi;
            dq_lo_hold   := fpga_out.dq_lo;
            rwds_out_pin <= fpga_out.rwds_hi;
            rwds_lo_hold := fpga_out.rwds_lo;
            dq_oe_pin    <= fpga_out.dq_oe;
            rwds_oe_pin  <= fpga_out.rwds_oe;
            cs_n         <= fpga_out.cs_n;
        end if;
        if falling_edge(hr_clock) then
            dq_out_pin   <= dq_lo_hold;
            rwds_out_pin <= rwds_lo_hold;
        end if;
    end process;

    ck_ddio : process(ck_clock)
        variable lo_hold : std_logic;
    begin
        if rising_edge(ck_clock) then
            ck      <= fpga_out.ck_hi;
            lo_hold := fpga_out.ck_lo;
        end if;
        if falling_edge(ck_clock) then
            ck <= lo_hold;
        end if;
    end process;

    reset_n <= fpga_out.reset_n;
    dq   <= dq_out_pin when dq_oe_pin = '1' else (others => 'Z');
    rwds <= rwds_out_pin when rwds_oe_pin = '1' else 'Z';

    -- input registers: hi sampled on the rising edge, lo on the falling edge, presented
    -- together on the rising edge
    ddio_in : process(read_clock)
        variable lo_dq, previous_lo_dq : std_logic_vector(7 downto 0);
        variable lo_rwds, previous_lo_rwds : std_logic;
    begin
        if rising_edge(read_clock) then
            if lo_lags then
                fpga_in_model <= (dq_hi => to_x01(dq), dq_lo => lo_dq, rwds_hi => to_x01(rwds), rwds_lo => lo_rwds);
            else
                fpga_in_model <= (dq_hi => previous_lo_dq, dq_lo => lo_dq, rwds_hi => previous_lo_rwds, rwds_lo => lo_rwds);
            end if;
            previous_lo_dq   := to_x01(dq);
            previous_lo_rwds := to_x01(rwds);
        end if;
        if falling_edge(read_clock) then
            lo_dq   := to_x01(dq);
            lo_rwds := to_x01(rwds);
        end if;
    end process;
    fpga_in <= (fpga_in_model.dq_hi, fpga_in_model.dq_lo, '0', '0') when rwds_cut else fpga_in_model;

    u_model : entity work.hyperram_model
    generic map(g_address_bits => model_bits, g_tckd => tckd_ns * 1 ns, g_tckdi => tckd_ns * 1 ns - 1.05 ns)
    port map(ck, cs_n, reset_n, dq, rwds);

------------------------------------------------------------------------
    dut : entity work.hyperram_core
    generic map(g_reset_low_clocks => 20, g_power_up_clocks => 100, g_settle_clocks => 20,
                g_phase_steps => phase_steps, g_min_window => 8, g_cal_attempts => 3)
    port map(
        clock => hr_clock, reset => reset, in_reset => in_reset,
        command_valid => command_valid, command_ready => command_ready, command_write => command_write,
        command_address => command_address, command_words => command_words,
        write_request => write_request, write_word => write_word, write_strobe => write_strobe,
        read_valid => read_valid, read_word => read_word, done => done,
        calibration_done => calibration_done, calibration_passed => calibration_passed,
        status => status, read_timeouts => read_timeouts, core_debug => core_debug,
        phase_shift => phase_shift, phase_shift_done => phase_shift_done,
        fpga_out => fpga_out, fpga_in => fpga_in);

------------------------------------------------------------------------
    -- the client: every write request answered on the edge it is seen; every read word taken
    client : process(hr_clock)
    begin
        if rising_edge(hr_clock) then
            if w_clear then
                w_index <= 0;
            elsif write_request then
                write_word   <= w_words(w_index);
                write_strobe <= w_strobes(w_index);
                w_index <= w_index + 1;
            end if;
            if r_clear then
                r_count <= 0;
            elsif read_valid then
                r_words(r_count) <= read_word;
                r_count <= r_count + 1;
            end if;
        end if;
    end process;

------------------------------------------------------------------------
    main : process
        -- the memory as the model holds it: word index of the model (die 1 above), bytes known
        type shadow_array is array (0 to 2**(model_bits+1)-1) of std_logic_vector(15 downto 0);
        variable shadow : shadow_array := (others => (others => '0'));
        type known_array is array (0 to 2**(model_bits+1)-1) of std_logic_vector(1 downto 0);
        variable known  : known_array := (others => "00");
        variable x      : unsigned(31 downto 0) := x"0bad_cafe";
        variable errors : natural := 0;

        impure function next_random return unsigned is
        begin
            x := resize(x * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
            return x;
        end function;

        -- the model's index of a word address: the die, then the model's bits of the word
        function model_index(address : natural) return natural is
            variable a : unsigned(24 downto 0) := to_unsigned(address, 25);
        begin
            return to_integer(a(24) & a(model_bits-1 downto 0));
        end function;

        procedure command(write : boolean; address, words : natural) is
        begin
            wait until rising_edge(hr_clock) and command_ready;
            command_valid   <= true;
            command_write   <= write;
            command_address <= to_unsigned(address, 25);
            command_words   <= words;
            wait until rising_edge(hr_clock);
            command_valid <= false;
            wait until rising_edge(hr_clock) and done for 50 us;
            check(done, "the transaction done");
        end procedure;

        -- words of random data and random strobes (a third of them partial) written at address
        procedure write_words(address, words : natural) is
            variable r : unsigned(31 downto 0);
            variable s : std_logic_vector(1 downto 0);
            variable i : natural;
        begin
            for k in 0 to words - 1 loop
                r := next_random;
                s := "11";
                if to_integer(r(31 downto 28)) < 5 then
                    s := std_logic_vector(r(27 downto 26));
                end if;
                w_words(k)   <= std_logic_vector(r(15 downto 0));
                w_strobes(k) <= s;
                i := model_index(address + k);
                if s(0) = '1' then shadow(i)(7 downto 0)  := std_logic_vector(r(7 downto 0));  known(i)(0) := '1'; end if;
                if s(1) = '1' then shadow(i)(15 downto 8) := std_logic_vector(r(15 downto 8)); known(i)(1) := '1'; end if;
            end loop;
            w_clear <= true;
            wait until rising_edge(hr_clock);
            w_clear <= false;
            command(true, address, words);
            check_equal(w_index, words, "every word asked for once");
        end procedure;

        -- words read at address, checked against the shadow
        procedure read_words(address, words : natural) is
            variable i : natural;
        begin
            r_clear <= true;
            wait until rising_edge(hr_clock);
            r_clear <= false;
            command(false, address, words);
            wait until rising_edge(hr_clock);
            check_equal(r_count, words, "every word given back");
            for k in 0 to words - 1 loop
                i := model_index(address + k);
                for b in 0 to 1 loop
                    if known(i)(b) = '1' and r_words(k)(8*b+7 downto 8*b) /= shadow(i)(8*b+7 downto 8*b) then
                        errors := errors + 1;
                        report "word " & integer'image(k) & " at " & integer'image(address + k) & ": "
                            & to_hstring(r_words(k)) & ", expected " & to_hstring(shadow(i)) & " (known "
                            & to_string(known(i)) & ")" severity error;
                    end if;
                end loop;
            end loop;
        end procedure;

        constant die_1 : natural := 2**24;
        variable timeouts_before : unsigned(15 downto 0);
    begin
        test_runner_setup(runner, runner_cfg);
        wait until calibration_done for 5 ms;
        check(calibration_done, "calibrated");
        info("calibration status " & to_hstring(status) & ", " & integer'image(to_integer(read_timeouts)) & " read timeouts");

        while test_suite loop
            if run("calibrates_on_both_dies") then
                check(calibration_passed, "a setting passed");
                check(status(0) = '1' and status(1) = '0', "the status: calibrated, a setting passed");
                if phase_steps > 0 then
                    info("relative phase: step " & integer'image(to_integer(unsigned(status(11 downto 4))))
                         & ", window " & integer'image(to_integer(unsigned(status(19 downto 12))))
                         & " steps, the other order's " & integer'image(to_integer(unsigned(status(27 downto 20))))
                         & ", " & integer'image(to_integer(unsigned(status(31 downto 28)))) & " sweeps");
                    check(status(3) = '0', "every step acknowledged");
                    check(to_integer(unsigned(status(19 downto 12))) >= 8, "a window of 8 steps or more");
                    check(to_integer(unsigned(status(19 downto 12))) < phase_steps, "a window with edges");
                end if;

            elsif run("writes_and_reads_back") then
                -- 1, 3 and 64 words, a whole 1 KB (512 words), the last words of die 0 and
                -- the first of die 1 (the model's bits of them)
                write_words(4096, 1);
                write_words(4100, 3);
                write_words(4608, 64);
                write_words(5120, 512);
                write_words(2**model_bits - 8, 8);
                write_words(die_1, 8);
                write_words(die_1 + 1000, 24);
                read_words(4096, 1);
                read_words(4100, 3);
                read_words(4608, 64);
                read_words(5120, 512);
                read_words(2**model_bits - 8, 8);
                read_words(die_1, 8);
                read_words(die_1 + 1000, 24);
                -- a read across written and unwritten words
                read_words(4096, 16);
                check_equal(errors, 0, "read back as written");

            elsif run("a_read_that_times_out_is_padded") then
                write_words(4096, 32);
                timeouts_before := read_timeouts;
                rwds_cut <= true;
                r_clear <= true;
                wait until rising_edge(hr_clock);
                r_clear <= false;
                command(false, 4096, 32);
                rwds_cut <= false;
                wait until rising_edge(hr_clock);
                check_equal(r_count, 32, "the timed out read's words given back");
                for k in 0 to 31 loop
                    check_equal(r_words(k), std_logic_vector'(x"0000"), "padded with zeros");
                end loop;
                check_equal(to_integer(read_timeouts - timeouts_before), 1, "a timeout counted");
                read_words(4096, 32);
                check_equal(errors, 0, "the next read right");
            end if;
        end loop;

        test_runner_cleanup(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 20 ms);

end vunit_simulation;
