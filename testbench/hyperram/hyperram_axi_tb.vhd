LIBRARY ieee  ;
    USE ieee.NUMERIC_STD.all  ;
    USE ieee.std_logic_1164.all  ;

library vunit_lib;
context vunit_lib.vunit_context;

    use work.hyperram_pkg.all;

-- hyperram_axi at 200 MHz with models of the DDIO pins, the PLL phase shift of the read clock
-- and the HyperRAM (both dies), driven like the Sapphire SoC's DDR port: commands on the
-- shared address channel, write data streamed with gaps, read data and write responses
-- taken with back-pressure. A shadow of the memory gives every read its expected data at
-- the time it is issued (the controller serves the commands in order).
--   tckd_ns      CK to DQ/RWDS delay of the memory model
--   lo_lags      pairing of the input DDIO halves, see the input register model
entity hyperram_axi_tb is
  generic (runner_cfg : string; tckd_ns : real := 3.0; lo_lags : boolean := true;
           word_count_start : natural := 0);
end;

architecture vunit_simulation of hyperram_axi_tb is

    constant hr_period  : time := 5 ns;
    constant phase_step : time := 250 ps;
    constant model_bits : natural := 14;            -- 16 K words a die in the model

    signal hr_clock   : std_logic := '0';
    signal ck_clock   : std_logic := '0';
    signal read_clock : std_logic := '0';
    signal read_delay : time := 0 ns;
    signal reset      : boolean := true;

    -- AXI
    signal arw_valid, arw_ready, arw_write : std_logic := '0';
    signal arw_addr  : std_logic_vector(31 downto 0) := (others => '0');
    signal arw_id, arw_len : std_logic_vector(7 downto 0) := (others => '0');
    signal arw_size  : std_logic_vector(2 downto 0) := "011";
    signal arw_burst : std_logic_vector(1 downto 0) := "01";
    signal w_valid, w_ready, w_last : std_logic := '0';
    signal w_data    : std_logic_vector(63 downto 0) := (others => '0');
    signal w_strb    : std_logic_vector(7 downto 0) := (others => '0');
    signal b_valid, b_ready : std_logic := '0';
    signal b_id      : std_logic_vector(7 downto 0);
    signal r_valid, r_ready, r_last : std_logic := '0';
    signal r_data    : std_logic_vector(63 downto 0);
    signal r_id      : std_logic_vector(7 downto 0);
    signal r_resp    : std_logic_vector(1 downto 0);

    signal calibration_done, calibration_passed : boolean;
    signal status        : std_logic_vector(31 downto 0);
    signal read_timeouts : unsigned(15 downto 0);
    signal phase_shift   : pll_phase_shift_record;
    signal fpga_out      : hyperram_ddr_fpga_out_record;
    signal fpga_in       : hyperram_ddr_fpga_in_record;

    -- pins
    signal ck, cs_n, reset_n : std_logic := '0';
    signal dq   : std_logic_vector(7 downto 0);
    signal rwds : std_logic;
    signal dq_out_pin  : std_logic_vector(7 downto 0) := (others => '0');
    signal rwds_out_pin, dq_oe_pin, rwds_oe_pin : std_logic := '0';

    -- the traffic: write beats to send, read beats and write responses to expect
    constant max_beats : natural := 65536;
    type data_array is array (natural range <>) of std_logic_vector(63 downto 0);
    type strb_array is array (natural range <>) of std_logic_vector(7 downto 0);
    type id_array is array (natural range <>) of std_logic_vector(7 downto 0);
    type bit_array is array (natural range <>) of std_logic;
    signal w_beats_data  : data_array(0 to max_beats-1);
    signal w_beats_strb  : strb_array(0 to max_beats-1);
    signal w_beats_last  : bit_array(0 to max_beats-1);
    signal w_beats_total : natural := 0;
    signal w_beats_sent  : natural := 0;
    signal r_expected    : data_array(0 to max_beats-1);
    signal r_known       : strb_array(0 to max_beats-1);    -- bytes with known contents
    signal r_exp_id      : id_array(0 to max_beats-1);
    signal r_exp_last    : bit_array(0 to max_beats-1);
    signal r_beats_total : natural := 0;
    signal r_beats_seen  : natural := 0;
    signal b_exp_id      : id_array(0 to 4095);
    signal b_total       : natural := 0;
    signal b_seen        : natural := 0;
    signal errors        : natural := 0;
    signal r_errors      : natural := 0;
    signal b_errors      : natural := 0;

    -- back-pressure and gaps, percent of clocks
    signal w_gap_percent, r_stall_percent, b_stall_percent : natural := 0;

    -- a small linear congruential generator
    function next_random(x : unsigned(31 downto 0)) return unsigned is
    begin
        return resize(x * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
    end function;

begin

    hr_clock   <= not hr_clock after hr_period/2;
    ck_clock   <= transport hr_clock after 3*hr_period/4;
    read_clock <= transport hr_clock after read_delay;
    reset      <= false after 100 ns;

    -- PLL dynamic phase shift: SHIFT is taken when SHIFT_ENA is high
    pll_model : process(phase_shift.shift_enable)
    begin
        if phase_shift.shift_enable = '1' and phase_shift.shift_select = "01000" then
            read_delay <= to_integer(unsigned(phase_shift.shift)) * phase_step;
        end if;
    end process;

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
                fpga_in <= (dq_hi => to_x01(dq), dq_lo => lo_dq, rwds_hi => to_x01(rwds), rwds_lo => lo_rwds);
            else
                fpga_in <= (dq_hi => previous_lo_dq, dq_lo => lo_dq, rwds_hi => previous_lo_rwds, rwds_lo => lo_rwds);
            end if;
            previous_lo_dq   := to_x01(dq);
            previous_lo_rwds := to_x01(rwds);
        end if;
        if falling_edge(read_clock) then
            lo_dq   := to_x01(dq);
            lo_rwds := to_x01(rwds);
        end if;
    end process;

    u_model : entity work.hyperram_model
    generic map(g_address_bits => model_bits, g_tckd => tckd_ns * 1 ns, g_tckdi => tckd_ns * 1 ns - 1.05 ns)
    port map(ck, cs_n, reset_n, dq, rwds);

------------------------------------------------------------------------
    dut : entity work.hyperram_axi
    generic map(g_reset_low_clocks => 20, g_power_up_clocks => 100, g_settle_clocks => 20,
                g_word_count_start => word_count_start)
    port map(
        clock      => hr_clock,
        reset      => reset,
        arw_valid  => arw_valid, arw_ready => arw_ready, arw_addr => arw_addr, arw_id => arw_id,
        arw_len    => arw_len, arw_size => arw_size, arw_burst => arw_burst, arw_write => arw_write,
        w_valid    => w_valid, w_ready => w_ready, w_data => w_data, w_strb => w_strb, w_last => w_last,
        b_valid    => b_valid, b_ready => b_ready, b_id => b_id,
        r_valid    => r_valid, r_ready => r_ready, r_data => r_data, r_id => r_id, r_resp => r_resp, r_last => r_last,
        calibration_done   => calibration_done,
        calibration_passed => calibration_passed,
        status             => status,
        read_timeouts      => read_timeouts,
        phase_shift        => phase_shift,
        fpga_out           => fpga_out,
        fpga_in            => fpga_in);

------------------------------------------------------------------------
    -- the write data, in the order of the write commands, with gaps
    write_driver : process(hr_clock)
        variable x : unsigned(31 downto 0) := x"0000_1234";
        variable next_beat : natural := 0;
    begin
        if rising_edge(hr_clock) then
            next_beat := w_beats_sent;
            if w_valid = '1' and w_ready = '1' then
                next_beat := w_beats_sent + 1;
            end if;
            w_beats_sent <= next_beat;
            x := next_random(x);
            if next_beat < w_beats_total and to_integer(x(31 downto 24)) mod 100 >= w_gap_percent then
                w_valid <= '1';
                w_data  <= w_beats_data(next_beat);
                w_strb  <= w_beats_strb(next_beat);
                w_last  <= w_beats_last(next_beat);
            else
                w_valid <= '0';
            end if;
        end if;
    end process;

    -- the read data, checked beat by beat
    read_checker : process(hr_clock)
        variable x : unsigned(31 downto 0) := x"0000_5678";
        variable k : natural;
    begin
        if rising_edge(hr_clock) then
            if r_valid = '1' and r_ready = '1' then
                k := r_beats_seen;
                if k >= r_beats_total then
                    r_errors <= r_errors + 1;
                    report "read beat without a read" severity error;
                else
                    for b in 0 to 7 loop
                        if r_known(k)(b) = '1' and r_data(8*b+7 downto 8*b) /= r_expected(k)(8*b+7 downto 8*b) then
                            r_errors <= r_errors + 1;
                            report "read beat " & integer'image(k) & " byte " & integer'image(b) & ": "
                                & to_hstring(r_data) & ", expected " & to_hstring(r_expected(k))
                                & " (known " & to_hstring(r_known(k)) & ")" severity error;
                            exit;
                        end if;
                    end loop;
                    if r_id /= r_exp_id(k) or r_last /= r_exp_last(k) or r_resp /= "00" then
                        r_errors <= r_errors + 1;
                        report "read beat " & integer'image(k) & ": id " & to_hstring(r_id) & " last " & std_logic'image(r_last)
                            & ", expected " & to_hstring(r_exp_id(k)) & " " & std_logic'image(r_exp_last(k)) severity error;
                    end if;
                end if;
                r_beats_seen <= k + 1;
            end if;
            x := next_random(x);
            r_ready <= '1' when to_integer(x(31 downto 24)) mod 100 >= r_stall_percent else '0';
        end if;
    end process;

    -- the write responses, in order
    response_checker : process(hr_clock)
        variable x : unsigned(31 downto 0) := x"0000_9abc";
    begin
        if rising_edge(hr_clock) then
            if b_valid = '1' and b_ready = '1' then
                if b_seen >= b_total or b_id /= b_exp_id(b_seen) then
                    b_errors <= b_errors + 1;
                    report "write response " & integer'image(b_seen) & ": id " & to_hstring(b_id) severity error;
                end if;
                b_seen <= b_seen + 1;
            end if;
            x := next_random(x);
            b_ready <= '1' when to_integer(x(31 downto 24)) mod 100 >= b_stall_percent else '0';
        end if;
    end process;

------------------------------------------------------------------------
    main : process
        -- the memory as the model holds it: word index of the model, first byte in 15:8
        type shadow_array is array (0 to 2**(model_bits+1)-1) of std_logic_vector(15 downto 0);
        variable shadow : shadow_array := (others => (others => '0'));
        type known_array is array (0 to 2**(model_bits+1)-1) of std_logic_vector(1 downto 0);
        variable known  : known_array := (others => "00");
        variable x      : unsigned(31 downto 0) := x"0bad_cafe";
        variable w_total, r_total, b_count : natural := 0;
        variable next_id : natural := 0;
        variable calibration_timeouts : unsigned(15 downto 0) := (others => '0');

        impure function random(n : positive) return natural is
        begin
            x := next_random(x);
            return to_integer(x(31 downto 8)) mod n;
        end function;

        function index_of(byte_address : natural) return natural is
            variable word : unsigned(24 downto 0);
        begin
            word := to_unsigned((byte_address / 2) mod 2**25, 25);
            return to_integer(word(24) & word(model_bits-1 downto 0));
        end function;

        -- one burst on the address channel; its data or its expected data queued
        procedure command(write : boolean; address : natural; beats : positive; strobes_random : boolean := false) is
            variable id   : std_logic_vector(7 downto 0);
            variable data : std_logic_vector(63 downto 0);
            variable strb : std_logic_vector(7 downto 0);
            variable kn   : std_logic_vector(7 downto 0);
            variable byte_address, i, lane : natural;
        begin
            id := std_logic_vector(to_unsigned(next_id mod 256, 8));
            next_id := next_id + 1;
            for beat in 0 to beats - 1 loop
                byte_address := (address / 8) * 8 + 8 * beat;
                if write then
                    for b in 0 to 7 loop
                        data(8*b+7 downto 8*b) := std_logic_vector(to_unsigned(random(256), 8));
                        if strobes_random then
                            strb(b) := '1' when random(4) /= 0 else '0';
                        else
                            strb(b) := '1';
                        end if;
                    end loop;
                    w_beats_data(w_total) <= data;
                    w_beats_strb(w_total) <= strb;
                    w_beats_last(w_total) <= '1' when beat = beats - 1 else '0';
                    w_total := w_total + 1;
                    -- lane 2k is the first byte of word k
                    for b in 0 to 7 loop
                        if strb(b) = '1' then
                            i := index_of(byte_address + b);
                            lane := (1 - b mod 2) * 8;     -- first byte in 15:8
                            shadow(i)(lane + 7 downto lane) := data(8*b+7 downto 8*b);
                            known(i)(1 - b mod 2) := '1';
                        end if;
                    end loop;
                else
                    for b in 0 to 7 loop
                        i := index_of(byte_address + b);
                        lane := (1 - b mod 2) * 8;
                        data(8*b+7 downto 8*b) := shadow(i)(lane + 7 downto lane);
                        kn(b) := known(i)(1 - b mod 2);
                    end loop;
                    r_expected(r_total) <= data;
                    r_known(r_total)    <= kn;
                    r_exp_id(r_total)   <= id;
                    r_exp_last(r_total) <= '1' when beat = beats - 1 else '0';
                    r_total := r_total + 1;
                end if;
            end loop;
            if write then
                b_exp_id(b_count) <= id;
                b_count := b_count + 1;
            end if;
            w_beats_total <= w_total;
            r_beats_total <= r_total;
            b_total       <= b_count;
            -- the address channel
            arw_valid <= '1';
            arw_write <= '1' when write else '0';
            arw_addr  <= std_logic_vector(to_unsigned(16#01000000# + address mod 2**26, 32));
            arw_id    <= id;
            arw_len   <= std_logic_vector(to_unsigned(beats - 1, 8));
            wait until rising_edge(hr_clock) and arw_ready = '1';
            arw_valid <= '0';
        end procedure;

        procedure wait_until_all_done(limit : time := 2 ms) is
        begin
            wait until rising_edge(hr_clock) and r_beats_seen = r_beats_total and b_seen = b_total
                and w_beats_sent = w_beats_total for limit;
            check(r_beats_seen = r_beats_total, "all read beats: " & integer'image(r_beats_seen) & " of " & integer'image(r_beats_total));
            check(b_seen = b_total, "all write responses: " & integer'image(b_seen) & " of " & integer'image(b_total));
            info(integer'image(r_beats_seen) & " read beats checked, " & integer'image(w_beats_sent)
                 & " write beats, " & integer'image(b_seen) & " write responses");
            check_equal(r_errors, 0, "read errors");
            check_equal(b_errors, 0, "write response errors");
            check_equal(read_timeouts, calibration_timeouts, "read timeouts after the calibration");
        end procedure;

        procedure write_and_read_back(address : natural; beats : positive; strobes_random : boolean := false) is
        begin
            command(true, address, beats, strobes_random);
            command(false, address, beats);
        end procedure;

        variable address, beats : natural;
        variable t0 : time;
    begin
        test_runner_setup(runner, runner_cfg);
        wait until calibration_done for 1 ms;
        check(calibration_done, "calibrated");
        info("calibration status " & to_hstring(status) & ", " & integer'image(to_integer(read_timeouts))
             & " reads timed out at failing settings");
        calibration_timeouts := read_timeouts;

        while test_suite loop
            if run("calibrates_on_both_dies") then
                check(calibration_passed, "a setting passed");
                check_equal(status(27) = '1', lo_lags, "order of the input halves");
                check(status(8 + 8*boolean'pos(status(27) = '1') + to_integer(unsigned(status(26 downto 24)))) = '1',
                      "the selected phase passed");

            elsif run("single_beats") then
                write_and_read_back(16#1000#, 1);
                write_and_read_back(16#2000008#, 1);       -- die 1
                write_and_read_back(16#1010#, 1, strobes_random => true);
                write_and_read_back(16#1018#, 1, strobes_random => true);
                command(false, 16#1000#, 4);
                wait_until_all_done;

            elsif run("byte_strobes_keep_the_other_bytes") then
                command(true, 16#3000#, 32);
                for k in 0 to 7 loop
                    command(true, 16#3000#, 32, strobes_random => true);
                end loop;
                command(false, 16#3000#, 32);
                wait_until_all_done;

            elsif run("bursts_across_1k_and_the_die_boundary") then
                -- 256 beats (2 KB) from 1 KB below the die boundary: 3 transactions
                write_and_read_back(16#1FFFC00#, 256);
                write_and_read_back(16#1FFFD08#, 200);     -- unaligned to 1 KB
                write_and_read_back(16#3F8#, 3);           -- across one 1 KB boundary
                command(false, 16#1FFFC00#, 256);
                wait_until_all_done;

            elsif run("random_traffic_with_back_pressure") then
                w_gap_percent   <= 30;
                r_stall_percent <= 40;
                b_stall_percent <= 60;
                for k in 0 to 299 loop
                    -- addresses in two windows, one on each die, so reads find written data
                    address := random(16#4000#) * 8 + 16#1000# + 16#2000000# * random(2);
                    beats   := 1 + random(256) when random(3) = 0 else 1 + random(16);
                    command(random(2) = 0, address, beats, strobes_random => random(2) = 0);
                end loop;
                wait_until_all_done(20 ms);

            elsif run("long_random_cpu_like_traffic") then
                -- mostly the CPU's cache lines (1 and 8 beats) and short DMA bursts, long stalls
                w_gap_percent   <= 50;
                r_stall_percent <= 70;
                b_stall_percent <= 80;
                for k in 0 to 1999 loop
                    address := random(16#2000#) * 8 + 16#1000# + 16#2000000# * random(2);
                    case random(8) is
                        when 0 to 3 => beats := 1;
                        when 4 to 5 => beats := 8;
                        when 6      => beats := 1 + random(32);
                        when others => beats := 1 + random(256);
                    end case;
                    command(random(3) /= 0, address, beats, strobes_random => random(2) = 0);
                end loop;
                wait_until_all_done(40 ms);

            elsif run("throughput") then
                -- 64 KB written and read back in 2 KB bursts, no back-pressure
                t0 := now;
                for k in 0 to 31 loop
                    command(true, 16#10000# + 2048*k, 256);
                end loop;
                wait until rising_edge(hr_clock) and b_seen = b_total for 2 ms;
                info("writes: " & integer'image(65536 * 1000 / ((now - t0) / 1 ns)) & " MB/s");
                t0 := now;
                for k in 0 to 31 loop
                    command(false, 16#10000# + 2048*k, 256);
                end loop;
                wait until rising_edge(hr_clock) and r_beats_seen = r_beats_total for 2 ms;
                info("reads: " & integer'image(65536 * 1000 / ((now - t0) / 1 ns)) & " MB/s");
                wait_until_all_done;
            end if;
        end loop;

        test_runner_cleanup(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 100 ms);

end vunit_simulation;
