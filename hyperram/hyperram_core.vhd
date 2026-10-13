library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.hyperram_pkg.all;

-- HyperRAM (W959D8NFYA, x8, two 32 MB dies) with a native interface of its own: transactions of
-- 16 bit words, one at a time. Everything that talks to the memory is here (its reset and power
-- up, the transactions' pins and timing, the read capture, the read clock's calibration);
-- hyperram_axi puts an AXI3 port in front of it. One clock: the HyperRAM clock (CK frequency,
-- 200 MHz); only the pins' input registers are on the phase shifted read clock.
--
-- The pins and their timing: CK runs only while CS# is low, the command/address takes cycles 1
-- to 3 of a transaction, data starts in cycle 2*g_latency + 3 (fixed latency, the configuration
-- registers' defaults), one word a cycle. CK stops after the last data cycle of reads too: the
-- memory never bursts past the words asked for.
--
-- Read data: the input DDIO registers at the pins are clocked by the read clock, the HyperRAM
-- clock delayed by 0..1.75 ns (the calibrated phase, 8 steps of 0.25 ns). Their outputs go
-- straight into a register on this clock a cycle later: a transfer between two clocks of one
-- frequency at a known phase, which the timing constraints check (at most 3 ns from the input
-- registers), so nothing crosses clock domains through pointers or synchronisers. The words are
-- framed by RWDS from there, on this clock.
--
-- The native interface:
--   a word: bits 7:0 the first byte (on CK's rising edge: the lower byte address), 15:8 the
--   second; its write strobes, bit 0 the first byte's: '1' written, '0' masked (RWDS high).
--   command   command_valid with command_write, command_address (word address: byte address
--             bits 25:1, die 1 from 2**24) and command_words (1..512), taken when command_ready
--             (idle and calibrated): a transaction of that many words. It must not cross a 1 KB
--             boundary (512 words: CS# low at most 2.6 us, under tCSM's 4 us) nor the die
--             boundary.
--   write     the core asks for each word with write_request, one clock each; the client puts
--             the word and its strobes on write_word and write_strobe on the clock edge it sees
--             the request (a registered answer), the core takes them a clock later. Every
--             request must be answered: a HyperRAM burst cannot pause, so the client issues a
--             write only when all its words are at hand.
--   read      the words come back on read_valid and read_word, at most one a clock, no
--             back-pressure: the client issues a read only when it has room for all of it. A
--             read that times out (the memory's RWDS missing) is padded with zero words, so
--             every read gives back the words asked for.
--   done      a clock's pulse when a transaction has finished, a read's words all given back (a
--             timed out read's padding too); command_ready is low in its clock, so a client's
--             next command comes after it has seen it.
--
-- Calibration after power up: a pattern is written at g_calibration_address_0 (die 0) and
-- g_calibration_address_1 (die 1), then read back with every read clock phase and both orders
-- of the DDIO input halves; a setting passes when both dies read back right, the middle of the
-- widest window of passing phases is used. Commands are taken only after it. The two areas
-- (64 words each) are the core's.
--
-- status: bit0 calibrated, bit1 no setting passed (the default is used), bits 15:8 phases that
--         passed with the hi input half first, bits 23:16 with the lo half first, bits 26:24
--         selected phase, bit 27 selected order (lo half first)
-- core_debug: bits 3:0 the core's state, 7:4 the calibration's, 23:8 transactions started
entity hyperram_core is
    generic(
        g_latency            : natural range 3 to 7 := 7;
        g_reset_low_clocks   : positive := 400;       -- RESET# low, tRP > 200 ns
        g_power_up_clocks    : positive := 32000;     -- tVCS > 150 us
        g_read_timeout       : positive := 64;        -- CK cycles after the expected last word
        g_recovery_clocks    : positive := 10;        -- CS# high between transactions
        g_settle_clocks      : positive := 100;       -- after a read clock phase change
        g_calibration_address_0 : natural := 0;                    -- byte addresses, 128 bytes each
        g_calibration_address_1 : natural := 16#3FFFF80#;
        g_default_phase      : natural range 0 to 7 := 5;
        g_default_lo_first   : boolean := true;
        g_word_count_start   : natural := 0           -- simulation: the word counters' start, to test their wrap
    );
    port(
        clock          : in std_logic;     -- HyperRAM clock, 0 degrees
        reset          : in boolean;       -- the PLL not locked
        in_reset       : out boolean;      -- reset through two registers: the client's reset

        command_valid   : in boolean;
        command_ready   : out boolean;
        command_write   : in boolean;
        command_address : in unsigned(24 downto 0);
        command_words   : in natural range 1 to 512;

        write_request  : out boolean;
        write_word     : in std_logic_vector(15 downto 0);
        write_strobe   : in std_logic_vector(1 downto 0);

        read_valid     : out boolean;
        read_word      : out std_logic_vector(15 downto 0);

        done           : out boolean;

        calibration_done   : out boolean;
        calibration_passed : out boolean;
        status             : out std_logic_vector(31 downto 0);
        read_timeouts      : out unsigned(15 downto 0);
        core_debug         : out std_logic_vector(23 downto 0);

        phase_shift        : out pll_phase_shift_record;
        phase_shift_output : in natural range 0 to 4 := 3;   -- PLL output of the read clock
        fpga_out           : out hyperram_ddr_fpga_out_record;
        -- from the input DDIO registers, clocked by the read clock (the PLL's dynamic phase output)
        fpga_in            : in hyperram_ddr_fpga_in_record
    );
end entity hyperram_core;

architecture rtl of hyperram_core is

    constant max_words      : natural := 512;     -- of a transaction: 1 KB
    constant pattern_words  : natural := 64;

    function to_std(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

    -- the calibration pattern, word i (as hyperram_axi's 64 bit beats had it, beat i / 4)
    function pattern_word(i : natural) return std_logic_vector is
        variable r : std_logic_vector(15 downto 0);
    begin
        r := std_logic_vector(to_unsigned((i * 40503 + 12345) mod 65536, 16));
        -- alternating bits on the first words, every DQ toggles
        if i = 0 then
            r := x"AA55";
        elsif i = 1 then
            r := x"55AA";
        end if;
        return r;
    end function;

    -- the core
    type core_states is (reset_low, power_up, idle, transaction, finish, recovery);
    signal core_state : core_states := reset_low;
    signal counter    : natural range 0 to g_power_up_clocks := 0;
    type calibration_states is (write_die_0, write_die_1, set_phase, settle, read_die_0, read_die_1,
                                wait_words, next_setting, choose);
    signal calibration_state : calibration_states := write_die_0;
    signal setting       : natural range 0 to 15 := 0;      -- lo first = setting/8, phase = setting mod 8
    signal cal_timer     : natural range 0 to g_settle_clocks := 0;
    signal cal_ok        : boolean := true;
    signal cal_word      : natural range 0 to 2*pattern_words := 0;
    signal pass_map      : std_logic_vector(15 downto 0) := (others => '0');
    -- the window search, a setting a clock
    signal search_index  : natural range 0 to 16 := 0;
    signal run_start, best_start   : natural range 0 to 7 := 0;
    signal run_length, best_length : natural range 0 to 8 := 0;
    signal best_lo_first : boolean := false;
    signal calibrated    : boolean := false;
    signal cal_failed    : boolean := false;
    signal read_phase    : natural range 0 to 7 := 0;
    signal lo_first      : boolean := false;
    -- the reset (the PLL not locked, asynchronous) through two registers, so every register
    -- here sees it at the same clock
    signal reset_sync : std_logic_vector(1 downto 0) := "11";
    signal reset_i    : boolean := true;
    attribute async_reg : boolean;
    attribute async_reg of reset_sync : signal is true;
    -- the transaction in progress
    signal is_write       : boolean := false;
    signal is_calibration : boolean := false;
    signal t_words        : natural range 1 to max_words := 1;
    signal cycle          : natural range 0 to 1023 := 0;
    signal header         : hyperram_header := (others => '0');
    signal last_cycle     : natural range 0 to 1023 := 0;
    signal ck_enable      : boolean := false;
    signal timed_out      : boolean := false;
    signal recovery_count : natural range 0 to g_recovery_clocks + g_read_timeout + 2 := 0;
    signal timeouts       : unsigned(15 downto 0) := (others => '0');
    signal transactions   : unsigned(15 downto 0) := (others => '0');
    constant data_cycle   : natural := 2*g_latency + 3;
    signal write_request_r : boolean := false;
    signal done_r         : boolean := false;
    signal cs_n_r     : std_logic := '1';
    signal reset_n_r  : std_logic := '0';
    signal dq_hi_r, dq_lo_r : std_logic_vector(7 downto 0) := (others => '0');
    signal dq_oe_r    : std_logic := '0';
    signal rwds_hi_r, rwds_lo_r : std_logic := '0';
    signal rwds_oe_r  : std_logic := '0';
    signal ck_lo_r    : std_logic := '0';
    -- read clock phase stepping
    signal applied_phase  : natural range 0 to 7 := 0;
    signal phase_timer    : natural range 0 to 31 := 0;
    signal shift_r        : std_logic_vector(2 downto 0) := (others => '0');
    signal shift_enable_r : std_logic := '0';
    -- the capture: started by the core (its word count reset), enabled around the data
    signal capture_start  : boolean := false;
    signal capture_enable : boolean := false;
    signal capture_length : natural range 1 to max_words := 4;
    signal capture_count  : natural range 0 to max_words := 0;
    signal sampled        : hyperram_ddr_fpga_in_record := ((others => '0'), (others => '0'), '0', '0');
    signal previous_rwds  : std_logic := '0';
    signal previous_dq    : std_logic_vector(7 downto 0) := (others => '0');
    signal word_valid     : boolean := false;
    signal word_data      : std_logic_vector(15 downto 0) := (others => '0');
    -- the read words out: the captured ones, then zeros for the words of a timed out read (the
    -- core asks for them: pad_start, pad_request); the words expected and given out, for the
    -- simulation's check
    signal pad_start      : boolean := false;
    signal pad_request    : natural range 0 to max_words := 0;
    signal pad_remaining  : natural range 0 to max_words := 0;
    signal out_valid      : boolean := false;
    signal out_word       : std_logic_vector(15 downto 0) := (others => '0');
    constant word_count_start : unsigned(31 downto 0) := to_unsigned(g_word_count_start, 32);
    signal words_expected : unsigned(31 downto 0) := word_count_start;
    signal words_out      : unsigned(31 downto 0) := word_count_start;

begin

    synchronise_reset : process(clock)
    begin
        if rising_edge(clock) then
            reset_sync <= reset_sync(0) & to_std(reset);
            reset_i    <= reset_sync(1) = '1';
        end if;
    end process;
    in_reset <= reset_i;

    phase_shift.shift        <= shift_r;
    phase_shift.shift_select <= std_logic_vector(to_unsigned(2**phase_shift_output, 5)) when shift_enable_r = '1' else "00000";
    phase_shift.shift_enable <= shift_enable_r;

    -- not in done's clock: the client sees done, and settles its accounts, before its next command
    command_ready      <= core_state = idle and calibrated and not reset_i and not done_r;
    write_request      <= write_request_r;
    read_valid         <= out_valid and calibrated;
    read_word          <= out_word;
    done               <= done_r;
    calibration_done   <= calibrated;
    calibration_passed <= calibrated and not cal_failed;
    status <= x"0" & to_std(lo_first) & std_logic_vector(to_unsigned(read_phase, 3))
              & pass_map(15 downto 8) & pass_map(7 downto 0) & "000000" & to_std(cal_failed) & to_std(calibrated);
    read_timeouts <= timeouts;
    core_debug <= std_logic_vector(transactions)
                  & std_logic_vector(to_unsigned(calibration_states'pos(calibration_state), 4))
                  & std_logic_vector(to_unsigned(core_states'pos(core_state), 4));

------------------------------------------------------------------------
    core : process(clock)
        variable n    : natural;
        variable k    : natural;
        variable word : std_logic_vector(15 downto 0);
        variable strobe : std_logic_vector(1 downto 0);

        -- starts a transaction of 'count' words at word address 'address'
        procedure start(write, calibration : boolean; address : unsigned(24 downto 0); count : natural) is
        begin
            is_write       <= write;
            is_calibration <= calibration;
            t_words        <= count;
            header         <= build_hyperram_header(read_transaction => not write, register_space => false,
                                                    address => to_integer(address));
            last_cycle     <= data_cycle + count - 1;
            capture_length <= count;
            capture_enable <= false;
            capture_start  <= true;
            transactions   <= transactions + 1;
            timed_out      <= false;
            cycle          <= 0;
            cs_n_r         <= '0';          -- cycle 0, CK still stopped
            ck_enable      <= true;         -- CK runs from cycle 1
            if not write then
                words_expected <= words_expected + count;
            end if;
            core_state <= transaction;
        end procedure;

    begin
        if rising_edge(clock) then
            fpga_out.reset_n <= reset_n_r;

            capture_start   <= false;
            pad_start       <= false;
            write_request_r <= false;
            done_r          <= false;

            -- CK of the next cycle, the CK pin register samples this a quarter cycle later
            ck_lo_r <= to_std(ck_enable);

            -- read clock phase: SHIFT is set first, SHIFT_SEL and SHIFT_ENA follow and are
            -- held for more than four read clock cycles
            if phase_timer > 0 then
                phase_timer <= phase_timer - 1;
                if phase_timer = 20 then
                    shift_enable_r <= '1';
                elsif phase_timer = 10 then
                    shift_enable_r <= '0';
                end if;
            elsif read_phase /= applied_phase then
                shift_r       <= std_logic_vector(to_unsigned(read_phase, 3));
                applied_phase <= read_phase;
                phase_timer   <= 24;
            end if;

            CASE core_state is
                WHEN reset_low =>
                    reset_n_r <= '0';
                    if counter < g_reset_low_clocks then
                        counter <= counter + 1;
                    else
                        counter    <= 0;
                        core_state <= power_up;
                    end if;

                WHEN power_up =>
                    reset_n_r <= '1';
                    if counter < g_power_up_clocks then
                        counter <= counter + 1;
                    else
                        counter    <= 0;
                        core_state <= idle;
                    end if;

                WHEN idle =>
                    cs_n_r    <= '1';
                    dq_oe_r   <= '0';
                    rwds_oe_r <= '0';
                    ck_enable <= false;

                    if not calibrated then
                        ------------------------------------------------------------
                        CASE calibration_state is
                            WHEN write_die_0 =>
                                start(true, true, to_unsigned(g_calibration_address_0 / 2, 25), pattern_words);
                                calibration_state <= write_die_1;
                            WHEN write_die_1 =>
                                start(true, true, to_unsigned(g_calibration_address_1 / 2, 25), pattern_words);
                                calibration_state <= set_phase;
                            WHEN set_phase =>
                                read_phase <= setting mod 8;
                                lo_first   <= setting >= 8;
                                cal_timer  <= 0;
                                calibration_state <= settle;
                            WHEN settle =>
                                if phase_timer = 0 and read_phase = applied_phase then
                                    if cal_timer < g_settle_clocks then
                                        cal_timer <= cal_timer + 1;
                                    else
                                        cal_ok   <= true;
                                        cal_word <= 0;
                                        calibration_state <= read_die_0;
                                    end if;
                                end if;
                            WHEN read_die_0 =>
                                start(false, true, to_unsigned(g_calibration_address_0 / 2, 25), pattern_words);
                                calibration_state <= read_die_1;
                            WHEN read_die_1 =>
                                start(false, true, to_unsigned(g_calibration_address_1 / 2, 25), pattern_words);
                                calibration_state <= wait_words;
                            WHEN wait_words =>
                                if cal_word = 2*pattern_words then
                                    calibration_state <= next_setting;
                                end if;
                            WHEN next_setting =>
                                pass_map(setting) <= to_std(cal_ok);
                                if setting < 15 then
                                    setting <= setting + 1;
                                    calibration_state <= set_phase;
                                else
                                    calibration_state <= choose;
                                end if;
                            WHEN choose =>
                                -- the middle of the widest window of passing phases, a setting a
                                -- clock (search_index), runs within each order of the halves
                                if search_index < 16 then
                                    if search_index mod 8 = 0 then
                                        run_length <= 0;
                                    end if;
                                    if pass_map(search_index) = '1' then
                                        if run_length = 0 or search_index mod 8 = 0 then
                                            run_start  <= search_index mod 8;
                                            run_length <= 1;
                                            if best_length = 0 then
                                                best_start    <= search_index mod 8;
                                                best_length   <= 1;
                                                best_lo_first <= search_index >= 8;
                                            end if;
                                        else
                                            run_length <= run_length + 1;
                                            if run_length + 1 > best_length then
                                                best_start    <= run_start;
                                                best_length   <= run_length + 1;
                                                best_lo_first <= search_index >= 8;
                                            end if;
                                        end if;
                                    else
                                        run_length <= 0;
                                    end if;
                                    search_index <= search_index + 1;
                                else
                                    if best_length = 0 then
                                        cal_failed <= true;
                                        read_phase <= g_default_phase;
                                        lo_first   <= g_default_lo_first;
                                    else
                                        read_phase <= best_start + (best_length - 1) / 2;
                                        lo_first   <= best_lo_first;
                                    end if;
                                    calibrated <= true;
                                end if;
                        end CASE;

                    elsif command_valid and not done_r then
                        -- synthesis translate_off
                        assert to_integer(command_address(8 downto 0)) + command_words <= max_words
                            report "hyperram_core: a transaction across a 1 KB boundary" severity error;
                        -- synthesis translate_on
                        start(command_write, false, command_address, command_words);
                    end if;

                WHEN transaction =>
                    -- the outputs set here are those of cycle 'cycle + 1'
                    cycle <= cycle + 1;
                    n := cycle + 1;
                    if n <= 3 then
                        dq_hi_r <= get_header_byte(header, 2*cycle);
                        dq_lo_r <= get_header_byte(header, 2*cycle + 1);
                        dq_oe_r <= '1';
                    elsif not is_write then
                        dq_oe_r <= '0';
                        -- the capture starts a cycle before the first data word reaches the pins:
                        -- it is two clocks later behind the input and transfer registers
                        if n + 1 >= data_cycle then
                            capture_enable <= true;
                        end if;
                        -- CK stops after the last data cycle, so the memory never bursts past
                        -- the words asked for (across a die boundary); CS# stays low until they
                        -- are in
                        if n = last_cycle then
                            ck_enable <= false;
                        end if;
                        if (n >= data_cycle and capture_count >= t_words) or n > last_cycle + g_read_timeout then
                            timed_out  <= capture_count < t_words;
                            ck_enable  <= false;
                            core_state <= finish;
                        end if;
                    else
                        -- write data: the client's word for cycle n was asked for two clocks
                        -- before (its answer registered a clock after the request); the
                        -- calibration's from the pattern
                        if not is_calibration and n + 2 >= data_cycle and n + 2 <= last_cycle then
                            write_request_r <= true;
                        end if;
                        if n >= data_cycle and n <= last_cycle then
                            k := n - data_cycle;
                            if is_calibration then
                                word   := pattern_word(k);
                                strobe := "11";
                            else
                                word   := write_word;
                                strobe := write_strobe;
                            end if;
                            dq_hi_r   <= word(7 downto 0);
                            dq_lo_r   <= word(15 downto 8);
                            rwds_hi_r <= not strobe(0);
                            rwds_lo_r <= not strobe(1);
                            dq_oe_r   <= '1';
                        else
                            dq_oe_r   <= '0';
                            rwds_hi_r <= '0';
                            rwds_lo_r <= '0';
                        end if;
                        -- RWDS is the data mask, driven from the cycle before the data
                        if n + 1 >= data_cycle and n <= last_cycle then
                            rwds_oe_r <= '1';
                        else
                            rwds_oe_r <= '0';
                        end if;
                        if n = last_cycle then
                            ck_enable  <= false;    -- no CK after the last data cycle
                            core_state <= finish;
                        end if;
                    end if;

                WHEN finish =>
                    -- CS# goes high with CK stopped low
                    cs_n_r    <= '1';
                    dq_oe_r   <= '0';
                    rwds_oe_r <= '0';
                    capture_enable <= false;
                    recovery_count <= 0;
                    if not is_write and timed_out then
                        timeouts <= timeouts + 1;
                    end if;
                    core_state <= recovery;

                WHEN recovery =>
                    -- tRWR and tCSHI between transactions; after a timed out read the words
                    -- still under way are let in before the rest are padded
                    if recovery_count < g_recovery_clocks + g_read_timeout + 2 then
                        recovery_count <= recovery_count + 1;
                    end if;
                    if timed_out and recovery_count = g_read_timeout then
                        pad_request <= t_words - capture_count;
                        pad_start   <= true;
                    end if;
                    -- after a timed out read, done once its padding is out too: every word given back
                    if recovery_count >= g_recovery_clocks and
                       (not timed_out or (recovery_count > g_read_timeout + 1 and pad_remaining = 0)) then
                        if not is_calibration then
                            done_r <= true;
                        end if;
                        core_state <= idle;
                    end if;
            end CASE;

            -- the calibration's reads: their words checked here
            if out_valid and not calibrated then
                if out_word /= pattern_word(cal_word mod pattern_words) then
                    cal_ok <= false;
                end if;
                cal_word <= cal_word + 1;
            end if;

            if reset_i then
                core_state        <= reset_low;
                counter           <= 0;
                calibrated        <= false;
                cal_failed        <= false;
                calibration_state <= write_die_0;
                setting           <= 0;
                pass_map          <= (others => '0');
                search_index      <= 0;
                best_length       <= 0;
                run_length        <= 0;
                words_expected    <= word_count_start;
                cs_n_r            <= '1';
                ck_enable         <= false;
                dq_oe_r           <= '0';
                rwds_oe_r         <= '0';
            end if;
        end if;
    end process;

    fpga_out.cs_n    <= cs_n_r;
    fpga_out.dq_hi   <= dq_hi_r;
    fpga_out.dq_lo   <= dq_lo_r;
    fpga_out.dq_oe   <= dq_oe_r;
    fpga_out.rwds_hi <= rwds_hi_r;
    fpga_out.rwds_lo <= rwds_lo_r;
    fpga_out.rwds_oe <= rwds_oe_r;
    fpga_out.ck_hi   <= '0';
    fpga_out.ck_lo   <= ck_lo_r;

------------------------------------------------------------------------
    -- read capture: the input registers' samples taken on this clock (the transfer from the
    -- read clock), then framed: RWDS is high with the first byte of a word and low with the
    -- second. The two samples of each cycle are put in time order, then a word starts at each
    -- sample with RWDS high: either within this cycle, or at the later sample of the previous
    -- cycle. At most one word a clock.
    capture : process(clock)
        variable word      : std_logic_vector(15 downto 0);
        variable has_word  : boolean;
        variable first_dq, second_dq     : std_logic_vector(7 downto 0);
        variable first_rwds, second_rwds : std_logic;
    begin
        if rising_edge(clock) then
            sampled    <= fpga_in;
            word_valid <= false;

            if lo_first then
                first_dq  := sampled.dq_lo;  first_rwds  := sampled.rwds_lo;
                second_dq := sampled.dq_hi;  second_rwds := sampled.rwds_hi;
            else
                first_dq  := sampled.dq_hi;  first_rwds  := sampled.rwds_hi;
                second_dq := sampled.dq_lo;  second_rwds := sampled.rwds_lo;
            end if;

            -- the word in byte address order: the first byte in bits 7:0
            has_word := false;
            if first_rwds = '1' then
                word     := second_dq & first_dq;
                has_word := true;
            elsif previous_rwds = '1' then
                word     := first_dq & previous_dq;
                has_word := true;
            end if;
            previous_rwds <= second_rwds;
            previous_dq   <= second_dq;

            if capture_start then
                capture_count <= 0;
            elsif capture_enable and has_word and capture_count < capture_length then
                word_data     <= word;
                word_valid    <= true;
                capture_count <= capture_count + 1;
            end if;
        end if;
    end process;

------------------------------------------------------------------------
    -- the read words out: the captured ones, then zeros for the words of a timed out read
    read_out : process(clock)
    begin
        if rising_edge(clock) then
            out_valid <= false;
            if word_valid then
                out_word  <= word_data;
                out_valid <= true;
            elsif pad_remaining > 0 then
                out_word      <= (others => '0');
                out_valid     <= true;
                pad_remaining <= pad_remaining - 1;
            end if;

            -- a timed out read's missing words, asked for once its words are all in
            if pad_start then
                pad_remaining <= pad_request;
            end if;

            if word_valid or pad_remaining > 0 then
                words_out <= words_out + 1;
                -- synthesis translate_off
                assert signed(words_expected - words_out) > 0
                    report "hyperram_core: a word no read asked for" severity error;
                -- synthesis translate_on
            end if;

            if reset_i then
                words_out     <= word_count_start;
                pad_remaining <= 0;
            end if;
        end if;
    end process;

end architecture rtl;
