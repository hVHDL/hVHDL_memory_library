library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.hyperram_pkg.all;
    use work.dual_port_ram_pkg.all;

-- HyperRAM (W959D8NFYA, x8, two 32 MB dies) behind an AXI3 port with a shared read/write
-- address channel, for the Sapphire SoC's DDR port: the whole 64 MB for the CPU and the
-- DMAs. One clock: the AXI port and the transactions run on the HyperRAM clock (CK
-- frequency, 200 MHz); only the pins' input registers are on the phase shifted read clock.
--
-- The pins and their timing: CK runs only while CS# is low, the command/address takes
-- cycles 1 to 3 of a transaction, data starts in cycle 2*g_latency + 3 (fixed latency, the
-- configuration registers' defaults), one 16 bit word a cycle. CK stops after the last data
-- cycle of reads too: the memory never bursts past the words asked for.
--
-- Read data: the input DDIO registers at the pins are clocked by the read clock, the HyperRAM
-- clock delayed by 0..1.75 ns (the calibrated phase, 8 steps of 0.25 ns). Their outputs go
-- straight into a register on this clock a cycle later: a transfer between two clocks of
-- one frequency at a known phase, which the timing constraints check (at most 3 ns from the
-- input registers), so nothing crosses clock domains through pointers or synchronisers.
-- The words are framed by RWDS from there, on this clock.
--
-- AXI:
--   addresses are HyperRAM byte addresses (bits 25:0 used, the SoC maps the memory at
--   0x01000000 without rebasing it), beats are 8 bytes (size 3) and aligned down to 8 bytes,
--   bursts INCR of up to 256 beats. Byte lane 2k of a beat is the first byte of word k (DQ on
--   the rising CK edge), lane 2k+1 its second; w_strb masks bytes with RWDS.
--   Transactions are served one at a time in the order of the address channel: R and B
--   come back in that order, with their ids.
--   A burst is split into HyperRAM transactions that do not cross a 1 KB boundary: at most
--   512 words (2.6 us of CS# low at 200 MHz, below tCSM 4 us), and never across the die
--   boundary at 0x2000000.
--   A write transaction starts when all its beats are in the write buffer (512 beats), so a
--   slow master cannot starve it; a read starts when the read buffer (256 beats) has room
--   for all of it, so a slow master cannot overflow it.
--
-- Calibration after power up: a pattern is written at g_calibration_address_0 (die 0) and
-- g_calibration_address_1 (die 1), then read back with every read clock phase and both
-- orders of the DDIO input halves; a setting passes when both dies read back right, the
-- middle of the widest window of passing phases is used. The AXI port is closed until
-- then. The two areas (64 words each) are the controller's.
--
-- status: bit0 calibrated, bit1 no setting passed (the default is used), bits 15:8 phases
--         that passed with the hi input half first, bits 23:16 with the lo half first, bits
--         26:24 selected phase, bit 27 selected order (lo half first)
entity hyperram_axi is
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
        clock          : in std_logic;     -- HyperRAM clock, 0 degrees, and the AXI clock
        reset          : in boolean;       -- the PLL not locked

        arw_valid      : in std_logic;
        arw_ready      : out std_logic;
        arw_addr       : in std_logic_vector(31 downto 0);
        arw_id         : in std_logic_vector(7 downto 0);
        arw_len        : in std_logic_vector(7 downto 0);
        arw_size       : in std_logic_vector(2 downto 0);
        arw_burst      : in std_logic_vector(1 downto 0);
        arw_write      : in std_logic;

        w_valid        : in std_logic;
        w_ready        : out std_logic;
        w_data         : in std_logic_vector(63 downto 0);
        w_strb         : in std_logic_vector(7 downto 0);
        w_last         : in std_logic;

        b_valid        : out std_logic;
        b_ready        : in std_logic;
        b_id           : out std_logic_vector(7 downto 0);

        r_valid        : out std_logic;
        r_ready        : in std_logic;
        r_data         : out std_logic_vector(63 downto 0);
        r_id           : out std_logic_vector(7 downto 0);
        r_resp         : out std_logic_vector(1 downto 0);
        r_last         : out std_logic;

        calibration_done   : out boolean;
        calibration_passed : out boolean;
        status             : out std_logic_vector(31 downto 0);
        read_timeouts      : out unsigned(15 downto 0);
        -- bits 3:0 the core's state, 7:4 the calibration's, 10:8 commands queued, 11 the head
        -- one is a write, 12 it waits for its data, 13 a read waits for room, 31:16
        -- transactions started (low 16 bits), 47:32 write beats buffered, 63:48 read beats
        -- issued and not yet out
        debug              : out std_logic_vector(63 downto 0);

        phase_shift        : out pll_phase_shift_record;
        phase_shift_output : in natural range 0 to 4 := 3;   -- PLL output of the read clock
        fpga_out           : out hyperram_ddr_fpga_out_record;
        -- from the input DDIO registers, clocked by the read clock (the PLL's dynamic phase output)
        fpga_in            : in hyperram_ddr_fpga_in_record
    );
end entity hyperram_axi;

architecture rtl of hyperram_axi is

    constant max_beats      : natural := 128;     -- of a HyperRAM transaction: 1 KB, 512 words
    constant pattern_beats  : natural := 16;      -- 64 words

    function to_std(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

    -- the calibration pattern, beat i
    function pattern(i : natural) return std_logic_vector is
        variable r : std_logic_vector(63 downto 0);
    begin
        for k in 0 to 3 loop
            r(16*k+15 downto 16*k) := std_logic_vector(to_unsigned(((4*i + k) * 40503 + 12345) mod 65536, 16));
        end loop;
        -- alternating bits on the first words, every DQ toggles
        if i = 0 then
            r(31 downto 0) := x"55AA_AA55";
        end if;
        return r;
    end function;

    ------------------------------------------------------------------------
    -- the address channel's queue: 4 entries, pointers counting in 0..7
    type command_record is record
        write        : boolean;
        id           : std_logic_vector(7 downto 0);
        beat_address : unsigned(22 downto 0);    -- byte address bits 25:3
        beats        : natural range 1 to 256;
    end record;
    type command_array is array (0 to 3) of command_record;
    signal commands : command_array := (others => (false, (others => '0'), (others => '0'), 1));
    signal command_tail, command_head : unsigned(2 downto 0) := (others => '0');
    signal writes_accepted : unsigned(3 downto 0) := (others => '0');

    -- write responses: 8 ids, filled by the core, emptied by the B channel
    type id_array is array (0 to 7) of std_logic_vector(7 downto 0);
    signal b_ids  : id_array := (others => (others => '0'));
    signal b_tail, b_head : unsigned(3 downto 0) := (others => '0');

    -- read transactions issued: the id, beats and whether it ends a burst, for the R channel
    type read_meta_record is record
        id    : std_logic_vector(7 downto 0);
        beats : natural range 1 to max_beats;
        last  : boolean;
    end record;
    type read_meta_array is array (0 to 7) of read_meta_record;
    signal read_meta : read_meta_array := (others => ((others => '0'), 1, false));
    signal meta_tail, meta_head : unsigned(3 downto 0) := (others => '0');

    ------------------------------------------------------------------------
    -- write buffer: 512 beats of data and strobes
    constant write_ram_subtype : dpram_ref_record := create_ref_subtypes(datawidth => 72, addresswidth => 9);
    constant write_ram_zeros   : ram_array(0 to 511)(71 downto 0) := (others => (others => '0'));
    signal write_ram_a_in, write_ram_b_in   : write_ram_subtype.ram_in'subtype;
    signal write_ram_a_out, write_ram_b_out : write_ram_subtype.ram_out'subtype;
    signal w_written  : unsigned(15 downto 0) := (others => '0');    -- beats in, ever
    signal w_consumed : unsigned(15 downto 0) := (others => '0');    -- beats written to the memory, ever
    signal w_ready_i  : boolean;

    -- read buffer: 256 beats
    constant read_ram_subtype : dpram_ref_record := create_ref_subtypes(datawidth => 64, addresswidth => 8);
    constant read_ram_zeros   : ram_array(0 to 255)(63 downto 0) := (others => (others => '0'));
    signal read_ram_a_in, read_ram_b_in   : read_ram_subtype.ram_in'subtype;
    signal read_ram_a_out, read_ram_b_out : read_ram_subtype.ram_out'subtype;
    signal r_issued : unsigned(15 downto 0) := (others => '0');      -- beats of reads started, ever
    signal r_stored : unsigned(15 downto 0) := (others => '0');      -- beats into the buffer, ever
    signal r_taken  : unsigned(15 downto 0) := (others => '0');      -- beats read out of it, ever

    -- words of reads expected (the core) and put into beats (the packer), for the
    -- simulation's check; after a timed out read, the words it lacks are padded with zeros: the core
    -- asks for them (pad_start, pad_request), the packer counts them out
    constant word_count_start : unsigned(31 downto 0) := to_unsigned(g_word_count_start, 32);
    signal words_expected : unsigned(31 downto 0) := word_count_start;
    signal words_packed   : unsigned(31 downto 0) := word_count_start;
    signal pad_start      : boolean := false;
    signal pad_request    : natural range 0 to 4*max_beats := 0;
    signal pad_remaining  : natural range 0 to 4*max_beats := 0;

    ------------------------------------------------------------------------
    -- the core
    type core_states is (reset_low, power_up, idle, transaction, finish, recovery);
    signal core_state : core_states := reset_low;
    signal counter    : natural range 0 to g_power_up_clocks := 0;
    signal operational : boolean := false;      -- calibrated, the AXI port open

    type calibration_states is (write_die_0, write_die_1, set_phase, settle, read_die_0, read_die_1,
                                wait_beats, next_setting, done);
    signal calibration_state : calibration_states := write_die_0;
    signal setting       : natural range 0 to 15 := 0;      -- lo first = setting/8, phase = setting mod 8
    signal cal_timer     : natural range 0 to g_settle_clocks := 0;
    signal cal_ok        : boolean := true;
    signal cal_beat      : natural range 0 to 2*pattern_beats := 0;
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

    -- the transaction in progress
    signal head_progress : boolean := false;    -- the head command's progress is loaded
    -- the next transaction, prepared from the head command
    type transaction_record is record
        write   : boolean;
        id      : std_logic_vector(7 downto 0);
        address : unsigned(22 downto 0);
        beats   : natural range 1 to max_beats;
        last    : boolean;
    end record;
    signal next_t   : transaction_record := (false, (others => '0'), (others => '0'), 1, false);
    signal prepared : boolean := false;
    -- the reset (the PLL not locked, asynchronous) through two registers, so every register
    -- here sees it at the same clock
    signal reset_sync : std_logic_vector(1 downto 0) := "11";
    signal reset_i    : boolean := true;
    attribute async_reg : boolean;
    attribute async_reg of reset_sync : signal is true;
    signal head_address  : unsigned(22 downto 0) := (others => '0');
    signal head_left     : natural range 0 to 256 := 0;
    signal is_write      : boolean := false;
    signal is_calibration : boolean := false;
    signal t_beats       : natural range 1 to max_beats := 1;
    signal t_words       : natural range 1 to 4*max_beats := 4;
    signal t_id          : std_logic_vector(7 downto 0) := (others => '0');
    signal t_last        : boolean := false;
    signal cycle         : natural range 0 to 1023 := 0;
    signal header        : hyperram_header := (others => '0');
    signal last_cycle    : natural range 0 to 1023 := 0;
    signal ck_enable     : boolean := false;
    signal timed_out     : boolean := false;
    signal recovery_count : natural range 0 to g_recovery_clocks + g_read_timeout := 0;
    signal timeouts      : unsigned(15 downto 0) := (others => '0');
    signal transactions  : unsigned(15 downto 0) := (others => '0');
    signal waits_for_data, waits_for_room : boolean := false;

    constant data_cycle  : natural := 2*g_latency + 3;

    -- write data: the beat being sent and the next one from the buffer
    signal beat_now, beat_next : std_logic_vector(71 downto 0) := (others => '0');

    signal cs_n_r     : std_logic := '1';
    signal reset_n_r  : std_logic := '0';
    signal dq_hi_r, dq_lo_r : std_logic_vector(7 downto 0) := (others => '0');
    signal dq_oe_r    : std_logic := '0';
    signal rwds_hi_r, rwds_lo_r : std_logic := '0';
    signal rwds_oe_r  : std_logic := '0';
    signal ck_lo_r    : std_logic := '0';

    -- read clock phase stepping
    signal applied_phase : natural range 0 to 7 := 0;
    signal phase_timer   : natural range 0 to 31 := 0;
    signal shift_r       : std_logic_vector(2 downto 0) := (others => '0');
    signal shift_enable_r : std_logic := '0';

    -- the capture: started by the core (its word count reset), enabled around the data
    signal capture_start  : boolean := false;
    signal capture_enable : boolean := false;
    signal capture_length : natural range 1 to 4*max_beats := 4;
    signal capture_count  : natural range 0 to 4*max_beats := 0;
    signal sampled        : hyperram_ddr_fpga_in_record := ((others => '0'), (others => '0'), '0', '0');
    signal previous_rwds  : std_logic := '0';
    signal previous_dq    : std_logic_vector(7 downto 0) := (others => '0');
    signal word_valid     : boolean := false;
    signal word_data      : std_logic_vector(15 downto 0) := (others => '0');

    ------------------------------------------------------------------------
    -- the packer and the R channel
    signal packed       : std_logic_vector(63 downto 0) := (others => '0');
    signal packed_words : natural range 0 to 3 := 0;

    type out_array is array (0 to 3) of std_logic_vector(63 downto 0);
    signal out_data       : out_array := (others => (others => '0'));
    signal out_tail, out_head : unsigned(2 downto 0) := (others => '0');
    signal out_requested  : natural range 0 to 3 := 0;   -- RAM reads under way
    signal beat_in_meta   : natural range 0 to max_beats := 0;    -- beats of the head entry already out
    signal r_valid_i      : boolean;
    signal r_last_i       : boolean;
    signal cal_beat_valid : boolean;

    function words_of(beats : natural) return natural is
    begin
        return 4*beats;
    end function;

begin

    synchronise_reset : process(clock)
    begin
        if rising_edge(clock) then
            reset_sync <= reset_sync(0) & to_std(reset);
            reset_i    <= reset_sync(1) = '1';
        end if;
    end process;

    phase_shift.shift        <= shift_r;
    phase_shift.shift_select <= std_logic_vector(to_unsigned(2**phase_shift_output, 5)) when shift_enable_r = '1' else "00000";
    phase_shift.shift_enable <= shift_enable_r;

    calibration_done   <= calibrated;
    calibration_passed <= calibrated and not cal_failed;
    status <= x"0" & to_std(lo_first) & std_logic_vector(to_unsigned(read_phase, 3))
              & pass_map(15 downto 8) & pass_map(7 downto 0) & "000000" & to_std(cal_failed) & to_std(calibrated);
    read_timeouts <= timeouts;
    debug <= std_logic_vector(r_issued - r_taken) & std_logic_vector(w_written - w_consumed)
             & std_logic_vector(transactions) & "00" & to_std(waits_for_room) & to_std(waits_for_data)
             & to_std(next_t.write)
             & std_logic_vector(command_tail - command_head)
             & std_logic_vector(to_unsigned(calibration_states'pos(calibration_state), 4))
             & std_logic_vector(to_unsigned(core_states'pos(core_state), 4));

------------------------------------------------------------------------
    -- the address channel
    arw_ready <= to_std(operational and command_tail - command_head < 4 and writes_accepted - b_head < 8);

    address_channel : process(clock)
        variable c : command_record;
    begin
        if rising_edge(clock) then
            if arw_valid = '1' and operational and command_tail - command_head < 4 and writes_accepted - b_head < 8 then
                -- synthesis translate_off
                assert arw_size = "011" report "hyperram_axi: only 8 byte beats" severity error;
                assert arw_burst = "01" report "hyperram_axi: only INCR bursts" severity error;
                -- synthesis translate_on
                c.write        := arw_write = '1';
                c.id           := arw_id;
                c.beat_address := unsigned(arw_addr(25 downto 3));
                c.beats        := to_integer(unsigned(arw_len)) + 1;
                commands(to_integer(command_tail(1 downto 0))) <= c;
                command_tail <= command_tail + 1;
                if c.write then
                    writes_accepted <= writes_accepted + 1;
                end if;
            end if;
            if reset_i then
                command_tail    <= (others => '0');
                writes_accepted <= (others => '0');
            end if;
        end if;
    end process;

------------------------------------------------------------------------
    -- write data into the write buffer
    w_ready_i <= operational and w_written - w_consumed < 511;
    w_ready   <= to_std(w_ready_i);

    write_channel : process(clock)
    begin
        if rising_edge(clock) then
            write_ram_a_in.write_requested   <= '0';
            write_ram_a_in.read_is_requested <= '0';
            if w_valid = '1' and w_ready_i then
                write_ram_a_in.address         <= w_written(8 downto 0);
                write_ram_a_in.data            <= w_strb & w_data;
                write_ram_a_in.write_requested <= '1';
                w_written <= w_written + 1;
            end if;
            if reset_i then
                w_written <= (others => '0');
            end if;
        end if;
    end process;

    u_write_buffer : entity work.dual_port_ram
    generic map(g_dpram_subtype => write_ram_subtype, g_ram_init_values => write_ram_zeros, g_output_register => false)
    port map(clock => clock, ram_a_in => write_ram_a_in, ram_a_out => write_ram_a_out,
             ram_b_in => write_ram_b_in, ram_b_out => write_ram_b_out);

------------------------------------------------------------------------
    -- the B channel
    b_valid <= to_std(b_tail /= b_head);
    b_id    <= b_ids(to_integer(b_head(2 downto 0)));

    write_response : process(clock)
    begin
        if rising_edge(clock) then
            if b_ready = '1' and b_tail /= b_head then
                b_head <= b_head + 1;
            end if;
            if reset_i then
                b_head <= (others => '0');
            end if;
        end if;
    end process;

------------------------------------------------------------------------
    core : process(clock)
        variable n          : natural;
        variable beats      : natural range 0 to 256;
        variable address    : unsigned(22 downto 0);
        variable command    : command_record;
        variable word       : natural range 0 to 3;
        variable beat       : std_logic_vector(71 downto 0);
        variable start_one  : boolean;

        -- starts a transaction of 'beats' beats at 'address'
        procedure start(write, calibration : boolean; addr : unsigned(22 downto 0); count : natural;
                        id : std_logic_vector(7 downto 0); last : boolean) is
        begin
            is_write       <= write;
            is_calibration <= calibration;
            t_beats        <= count;
            t_words        <= words_of(count);
            t_id           <= id;
            t_last         <= last;
            header         <= build_hyperram_header(read_transaction => not write, register_space => false,
                                                    address => to_integer(addr & "00"));
            last_cycle     <= data_cycle + words_of(count) - 1;
            capture_length <= words_of(count);
            capture_enable <= false;
            capture_start  <= true;
            transactions   <= transactions + 1;
            timed_out      <= false;
            cycle          <= 0;
            cs_n_r         <= '0';          -- cycle 0, CK still stopped
            ck_enable      <= true;         -- CK runs from cycle 1
            if not write then
                words_expected <= words_expected + words_of(count);
                r_issued       <= r_issued + count;
                read_meta(to_integer(meta_tail(2 downto 0))) <= (id, count, last);
                meta_tail      <= meta_tail + 1;
            end if;
            core_state <= transaction;
        end procedure;

    begin
        if rising_edge(clock) then
            write_ram_b_in.read_is_requested <= '0';
            write_ram_b_in.write_requested   <= '0';
            fpga_out.reset_n <= reset_n_r;

            capture_start <= false;
            pad_start     <= false;

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

            -- the next write beat comes from the buffer, or the pattern
            if write_ram_b_out.data_is_ready = '1' then
                beat_next <= write_ram_b_out.data;
            end if;

            -- the next transaction prepared a clock ahead from the head command: at most to the
            -- next 1 KB boundary; the command leaves the queue with its last one
            if calibrated and not prepared and command_tail /= command_head then
                command := commands(to_integer(command_head(1 downto 0)));
                if head_progress then
                    address := head_address;
                    beats   := head_left;
                else
                    address := command.beat_address;
                    beats   := command.beats;
                end if;
                n := max_beats - to_integer(address(6 downto 0));
                if beats < n then
                    n := beats;
                end if;
                next_t   <= (command.write, command.id, address, n, n = beats);
                prepared <= true;
                if n = beats then
                    head_progress <= false;
                    command_head  <= command_head + 1;
                else
                    head_progress <= true;
                    head_address  <= address + n;
                    head_left     <= beats - n;
                end if;
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
                                beat_next <= x"FF" & pattern(0);
                                start(true, true, to_unsigned(g_calibration_address_0 / 8, 23), pattern_beats, x"00", false);
                                calibration_state <= write_die_1;
                            WHEN write_die_1 =>
                                beat_next <= x"FF" & pattern(0);
                                start(true, true, to_unsigned(g_calibration_address_1 / 8, 23), pattern_beats, x"00", false);
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
                                        cal_beat <= 0;
                                        calibration_state <= read_die_0;
                                    end if;
                                end if;
                            WHEN read_die_0 =>
                                start(false, true, to_unsigned(g_calibration_address_0 / 8, 23), pattern_beats, x"00", false);
                                calibration_state <= read_die_1;
                            WHEN read_die_1 =>
                                start(false, true, to_unsigned(g_calibration_address_1 / 8, 23), pattern_beats, x"00", false);
                                calibration_state <= wait_beats;
                            WHEN wait_beats =>
                                if cal_beat = 2*pattern_beats then
                                    calibration_state <= next_setting;
                                end if;
                            WHEN next_setting =>
                                pass_map(setting) <= to_std(cal_ok);
                                if setting < 15 then
                                    setting <= setting + 1;
                                    calibration_state <= set_phase;
                                else
                                    calibration_state <= done;
                                end if;
                            WHEN done =>
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

                    else
                        ------------------------------------------------------------
                        -- the prepared transaction (see below) once what it needs is there:
                        -- all its write data, or room for all its read data
                        operational <= true;
                        if prepared then
                            if next_t.write then
                                start_one := w_written - w_consumed >= next_t.beats;
                                waits_for_data <= not start_one;
                                waits_for_room <= false;
                                if start_one then
                                    write_ram_b_in.address <= w_consumed(8 downto 0);
                                    write_ram_b_in.read_is_requested <= '1';
                                end if;
                            else
                                start_one := r_issued - r_taken + next_t.beats <= 256 and meta_tail - meta_head < 8;
                                waits_for_room <= not start_one;
                                waits_for_data <= false;
                            end if;
                            if start_one then
                                start(next_t.write, false, next_t.address, next_t.beats, next_t.id, next_t.last);
                                prepared <= false;
                            end if;
                        end if;
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
                        -- write data: word k of the transaction is word k mod 4 of beat k/4;
                        -- the beat after it is fetched from the buffer meanwhile
                        if n >= data_cycle and n <= last_cycle then
                            word := (n - data_cycle) mod 4;
                            if word = 0 then
                                if is_calibration then
                                    beat := x"FF" & pattern((n - data_cycle) / 4);
                                else
                                    beat := beat_next;
                                end if;
                                beat_now <= beat;
                                if not is_calibration and (n - data_cycle) / 4 + 1 < t_beats then
                                    write_ram_b_in.address <= w_consumed(8 downto 0) + (n - data_cycle) / 4 + 1;
                                    write_ram_b_in.read_is_requested <= '1';
                                end if;
                            else
                                beat := beat_now;
                            end if;
                            dq_hi_r   <= beat(16*word + 7 downto 16*word);
                            dq_lo_r   <= beat(16*word + 15 downto 16*word + 8);
                            rwds_hi_r <= not beat(64 + 2*word);
                            rwds_lo_r <= not beat(64 + 2*word + 1);
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
                    if is_write then
                        if not is_calibration then
                            w_consumed <= w_consumed + t_beats;
                            if t_last then
                                b_ids(to_integer(b_tail(2 downto 0))) <= t_id;
                                b_tail <= b_tail + 1;
                            end if;
                        end if;
                    elsif timed_out then
                        timeouts <= timeouts + 1;
                    end if;
                    core_state <= recovery;

                WHEN recovery =>
                    -- tRWR and tCSHI between transactions; after a timed out read the words
                    -- still under way are let in before the rest of the beats are padded
                    recovery_count <= recovery_count + 1;
                    if timed_out and recovery_count = g_read_timeout then
                        pad_request <= t_words - capture_count;
                        pad_start   <= true;
                    end if;
                    if recovery_count >= g_recovery_clocks and (not timed_out or recovery_count > g_read_timeout) then
                        core_state <= idle;
                    end if;
            end CASE;

            -- the calibration's reads: their beats come back here instead of the R channel
            if cal_beat_valid then
                if out_data(to_integer(out_head(1 downto 0))) /= pattern(cal_beat mod pattern_beats) then
                    cal_ok <= false;
                end if;
                cal_beat <= cal_beat + 1;
            end if;

            if reset_i then
                core_state        <= reset_low;
                counter           <= 0;
                operational       <= false;
                calibrated        <= false;
                cal_failed        <= false;
                calibration_state <= write_die_0;
                setting           <= 0;
                pass_map          <= (others => '0');
                search_index      <= 0;
                best_length       <= 0;
                run_length        <= 0;
                command_head      <= (others => '0');
                head_progress     <= false;
                prepared          <= false;
                b_tail            <= (others => '0');
                meta_tail         <= (others => '0');
                w_consumed        <= (others => '0');
                r_issued          <= (others => '0');
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
    -- cycle. At most one word a clock, straight to the packer.
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

            has_word := false;
            if first_rwds = '1' then
                word     := first_dq & second_dq;
                has_word := true;
            elsif previous_rwds = '1' then
                word     := previous_dq & first_dq;
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
    -- words into beats, into the read buffer; zeros for the words of a timed out read
    packer : process(clock)
        variable word     : std_logic_vector(15 downto 0);
        variable has_word : boolean;
    begin
        if rising_edge(clock) then
            read_ram_a_in.write_requested   <= '0';
            read_ram_a_in.read_is_requested <= '0';
            has_word := false;
            if word_valid then
                word     := word_data;
                has_word := true;
            elsif pad_remaining > 0 then
                word     := (others => '0');
                has_word := true;
                pad_remaining <= pad_remaining - 1;
            end if;

            -- a timed out read's missing words, asked for once its words are all in
            if pad_start then
                pad_remaining <= pad_request;
            end if;

            if has_word then
                words_packed <= words_packed + 1;
                -- synthesis translate_off
                assert signed(words_expected - words_packed) > 0
                    report "hyperram_axi: a word no read asked for" severity error;
                -- synthesis translate_on
                packed(16*packed_words + 7 downto 16*packed_words)      <= word(15 downto 8);
                packed(16*packed_words + 15 downto 16*packed_words + 8) <= word(7 downto 0);
                if packed_words = 3 then
                    packed_words <= 0;
                    read_ram_a_in.address         <= r_stored(7 downto 0);
                    read_ram_a_in.data            <= word(7 downto 0) & word(15 downto 8) & packed(47 downto 0);
                    read_ram_a_in.write_requested <= '1';
                    r_stored <= r_stored + 1;
                else
                    packed_words <= packed_words + 1;
                end if;
            end if;

            if reset_i then
                words_packed  <= word_count_start;
                pad_remaining <= 0;
                packed_words <= 0;
                r_stored     <= (others => '0');
            end if;
        end if;
    end process;

    u_read_buffer : entity work.dual_port_ram
    generic map(g_dpram_subtype => read_ram_subtype, g_ram_init_values => read_ram_zeros, g_output_register => false)
    port map(clock => clock, ram_a_in => read_ram_a_in, ram_a_out => read_ram_a_out,
             ram_b_in => read_ram_b_in, ram_b_out => read_ram_b_out);

------------------------------------------------------------------------
    -- the R channel: beats from the read buffer through a 4 beat queue; the calibration's
    -- beats go to the core instead
    r_valid_i      <= out_tail /= out_head and calibrated;
    cal_beat_valid <= out_tail /= out_head and not calibrated;
    r_last_i       <= read_meta(to_integer(meta_head(2 downto 0))).last
                      and beat_in_meta + 1 = read_meta(to_integer(meta_head(2 downto 0))).beats;
    r_valid <= to_std(r_valid_i);
    r_data  <= out_data(to_integer(out_head(1 downto 0)));
    r_id    <= read_meta(to_integer(meta_head(2 downto 0))).id;
    r_resp  <= "00";
    r_last  <= to_std(r_last_i);

    read_channel : process(clock)
        variable taken     : boolean;
        variable in_flight : natural range 0 to 3;
    begin
        if rising_edge(clock) then
            read_ram_b_in.read_is_requested <= '0';
            read_ram_b_in.write_requested   <= '0';

            -- a beat leaves
            taken := (r_valid_i and r_ready = '1') or cal_beat_valid;
            if taken then
                out_head <= out_head + 1;
                if beat_in_meta + 1 = read_meta(to_integer(meta_head(2 downto 0))).beats then
                    beat_in_meta <= 0;
                    meta_head    <= meta_head + 1;
                else
                    beat_in_meta <= beat_in_meta + 1;
                end if;
            end if;

            -- a beat arrives from the RAM
            in_flight := out_requested;
            if read_ram_b_out.data_is_ready = '1' then
                out_data(to_integer(out_tail(1 downto 0))) <= read_ram_b_out.data;
                out_tail  <= out_tail + 1;
                in_flight := in_flight - 1;
            end if;

            -- the next read of the RAM when the queue has room for it and the reads under way
            if r_stored /= r_taken and to_integer(out_tail - out_head) + out_requested < 4 then
                read_ram_b_in.address           <= r_taken(7 downto 0);
                read_ram_b_in.read_is_requested <= '1';
                r_taken   <= r_taken + 1;
                in_flight := in_flight + 1;
            end if;
            out_requested <= in_flight;

            if reset_i then
                out_head     <= (others => '0');
                out_tail     <= (others => '0');
                beat_in_meta <= 0;
                meta_head    <= (others => '0');
                r_taken      <= (others => '0');
                out_requested <= 0;
            end if;
        end if;
    end process;

end architecture rtl;
