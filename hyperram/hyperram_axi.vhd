library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.hyperram_pkg.all;
    use work.dual_port_ram_pkg.all;

-- HyperRAM (W959D8NFYA, x8, two 32 MB dies) behind an AXI3 port with a shared read/write
-- address channel, for the Sapphire SoC's DDR port: the whole 64 MB for the CPU and the
-- DMAs. One clock: the AXI port and the transactions run on the HyperRAM clock (CK
-- frequency, 200 MHz). The memory itself, its pins, timing, read capture and calibration, is
-- hyperram_core's (its native interface of 16 bit words); this is the AXI3 port in front of it.
--
-- AXI:
--   addresses are HyperRAM byte addresses (bits 25:0 used, the SoC maps the memory at
--   0x01000000 without rebasing it), beats are 8 bytes (size 3) and aligned down to 8 bytes,
--   bursts INCR of up to 256 beats. Byte lane 2k of a beat is the first byte of word k (DQ on
--   the rising CK edge), lane 2k+1 its second: the beat's 16 bit lanes are the core's words;
--   w_strb masks bytes with RWDS.
--   Transactions are served one at a time in the order of the address channel: R and B
--   come back in that order, with their ids.
--   A burst is split into HyperRAM transactions that do not cross a 1 KB boundary: at most
--   512 words (2.6 us of CS# low at 200 MHz, below tCSM 4 us), and never across the die
--   boundary at 0x2000000.
--   A write transaction starts when all its beats are in the write buffer (512 beats): every
--   word the core asks for is there. A read starts when the read buffer (256 beats) has room
--   for all of it: the core's words are never held up.
--
-- Calibration after power up is the core's (hyperram_core): the AXI port is closed until then.
--
-- status: as hyperram_core's (its layout for a relative phase there); absolute phase: bit0
--         calibrated, bit1 no setting passed (the default is used),
--         bits 15:8 phases that passed with the hi input half first, bits 23:16 with the lo half
--         first, bits 26:24 selected phase, bit 27 selected order (lo half first)
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
        g_phase_steps        : natural := 0;          -- relative read clock phase, see hyperram_core
        g_min_window         : positive := 1;
        g_max_window         : natural := 0;
        g_phase_timeout      : positive := 50000;
        g_cal_attempts       : positive := 1;
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
        -- the core's calibration pass map, a step at a time (hyperram_core)
        map_index          : in natural range 0 to 255 := 0;
        map_bits           : out std_logic_vector(1 downto 0);
        -- bits 3:0 the core's state, 7:4 the calibration's, 10:8 commands queued, 11 the head
        -- one is a write, 12 it waits for its data, 13 a read waits for room, 31:16
        -- transactions started (low 16 bits), 47:32 write beats buffered, 63:48 read beats
        -- issued and not yet out
        debug              : out std_logic_vector(63 downto 0);

        phase_shift        : out pll_phase_shift_record;
        phase_shift_output : in natural range 0 to 4 := 3;   -- PLL output of the read clock
        phase_shift_done   : in std_logic := '0';             -- relative phase: a step applied
        fpga_out           : out hyperram_ddr_fpga_out_record;
        -- from the input DDIO registers, clocked by the read clock (the PLL's dynamic phase output)
        fpga_in            : in hyperram_ddr_fpga_in_record
    );
end entity hyperram_axi;

architecture rtl of hyperram_axi is

    constant max_beats : natural := 128;      -- of a HyperRAM transaction: 1 KB, 512 words

    function to_std(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
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

    -- write responses: 8 ids, filled when a burst's last write is done, emptied by the B channel
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

    ------------------------------------------------------------------------
    -- the core and its native interface
    signal reset_i        : boolean;
    signal calibrated     : boolean;
    signal command_valid  : boolean;
    signal command_ready  : boolean;
    signal core_write_request : boolean;
    signal core_write_word    : std_logic_vector(15 downto 0) := (others => '0');
    signal core_write_strobe  : std_logic_vector(1 downto 0) := (others => '0');
    signal core_read_valid    : boolean;
    signal core_read_word     : std_logic_vector(15 downto 0);
    signal core_done          : boolean;
    signal core_debug         : std_logic_vector(23 downto 0);

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
    signal head_progress : boolean := false;    -- the head command's progress is loaded
    signal head_address  : unsigned(22 downto 0) := (others => '0');
    signal head_left     : natural range 0 to 256 := 0;
    -- the transaction with the core: what its done ends
    signal t_write : boolean := false;
    signal t_beats : natural range 1 to max_beats := 1;
    signal t_id    : std_logic_vector(7 downto 0) := (others => '0');
    signal t_last  : boolean := false;
    signal waits_for_data, waits_for_room : boolean := false;
    signal start_one : boolean;

    -- write data to the core: the beat being sent and the next one from the buffer
    signal beat_now, beat_next : std_logic_vector(71 downto 0) := (others => '0');
    signal word_in_beat  : natural range 0 to 3 := 0;
    signal beats_fetched : natural range 0 to max_beats := 0;   -- of the transaction, from the buffer

    ------------------------------------------------------------------------
    -- the packer and the R channel
    signal packed       : std_logic_vector(47 downto 0) := (others => '0');
    signal packed_words : natural range 0 to 3 := 0;

    type out_array is array (0 to 3) of std_logic_vector(63 downto 0);
    signal out_data       : out_array := (others => (others => '0'));
    signal out_tail, out_head : unsigned(2 downto 0) := (others => '0');
    signal out_requested  : natural range 0 to 3 := 0;   -- RAM reads under way
    signal beat_in_meta   : natural range 0 to max_beats := 0;    -- beats of the head entry already out
    signal r_valid_i      : boolean;
    signal r_last_i       : boolean;

begin

    u_core : entity work.hyperram_core
    generic map(
        g_latency => g_latency, g_reset_low_clocks => g_reset_low_clocks,
        g_power_up_clocks => g_power_up_clocks, g_read_timeout => g_read_timeout,
        g_recovery_clocks => g_recovery_clocks, g_settle_clocks => g_settle_clocks,
        g_calibration_address_0 => g_calibration_address_0, g_calibration_address_1 => g_calibration_address_1,
        g_default_phase => g_default_phase, g_default_lo_first => g_default_lo_first,
        g_phase_steps => g_phase_steps, g_min_window => g_min_window, g_max_window => g_max_window,
        g_phase_timeout => g_phase_timeout,
        g_cal_attempts => g_cal_attempts,
        g_word_count_start => g_word_count_start)
    port map(
        clock => clock, reset => reset, in_reset => reset_i,
        command_valid => command_valid, command_ready => command_ready,
        command_write => next_t.write, command_address => next_t.address & "00",
        command_words => 4 * next_t.beats,
        write_request => core_write_request, write_word => core_write_word, write_strobe => core_write_strobe,
        read_valid => core_read_valid, read_word => core_read_word,
        done => core_done,
        calibration_done => calibrated, calibration_passed => calibration_passed,
        status => status, read_timeouts => read_timeouts, core_debug => core_debug,
        map_index => map_index, map_bits => map_bits,
        phase_shift => phase_shift, phase_shift_output => phase_shift_output,
        phase_shift_done => phase_shift_done,
        fpga_out => fpga_out, fpga_in => fpga_in);

    calibration_done <= calibrated;
    debug <= std_logic_vector(r_issued - r_taken) & std_logic_vector(w_written - w_consumed)
             & core_debug(23 downto 8) & "00" & to_std(waits_for_room) & to_std(waits_for_data)
             & to_std(next_t.write)
             & std_logic_vector(command_tail - command_head)
             & core_debug(7 downto 0);

------------------------------------------------------------------------
    -- the address channel
    arw_ready <= to_std(calibrated and command_tail - command_head < 4 and writes_accepted - b_head < 8);

    address_channel : process(clock)
        variable c : command_record;
    begin
        if rising_edge(clock) then
            if arw_valid = '1' and calibrated and command_tail - command_head < 4 and writes_accepted - b_head < 8 then
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
    w_ready_i <= calibrated and w_written - w_consumed < 511;
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
    -- the transactions: the next one prepared from the head command (at most to the next 1 KB
    -- boundary; the command leaves the queue with its last one), given to the core once what
    -- it needs is there: all its write data, or room for all its read data
    start_one <= prepared and ((next_t.write and w_written - w_consumed >= next_t.beats)
                 or (not next_t.write and r_issued - r_taken + next_t.beats <= 256 and meta_tail - meta_head < 8));
    command_valid <= start_one;

    transactions : process(clock)
        variable n       : natural;
        variable beats   : natural range 0 to 256;
        variable address : unsigned(22 downto 0);
        variable command : command_record;
    begin
        if rising_edge(clock) then
            write_ram_b_in.read_is_requested <= '0';
            write_ram_b_in.write_requested   <= '0';

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

            if prepared and command_ready then
                waits_for_data <= next_t.write and not start_one;
                waits_for_room <= not next_t.write and not start_one;
            end if;

            -- a transaction given to the core: a write's first beat fetched (the core asks for
            -- its first word some clocks later), a read's beats noted for the R channel
            if start_one and command_ready then
                prepared <= false;
                t_write  <= next_t.write;
                t_beats  <= next_t.beats;
                t_id     <= next_t.id;
                t_last   <= next_t.last;
                if next_t.write then
                    write_ram_b_in.address           <= w_consumed(8 downto 0);
                    write_ram_b_in.read_is_requested <= '1';
                    beats_fetched <= 1;
                    word_in_beat  <= 0;
                else
                    r_issued <= r_issued + next_t.beats;
                    read_meta(to_integer(meta_tail(2 downto 0))) <= (next_t.id, next_t.beats, next_t.last);
                    meta_tail <= meta_tail + 1;
                end if;
            end if;

            -- write data: a beat from the buffer a clock after its read
            if write_ram_b_out.data_is_ready = '1' then
                beat_next <= write_ram_b_out.data;
            end if;

            -- the word the core asks for, registered: word k of the transaction is word k mod 4 of
            -- beat k / 4; the beat after it is fetched as its first word goes
            if core_write_request then
                if word_in_beat = 0 then
                    beat_now          <= beat_next;
                    core_write_word   <= beat_next(15 downto 0);
                    core_write_strobe <= beat_next(65 downto 64);
                    if beats_fetched < t_beats then
                        write_ram_b_in.address           <= w_consumed(8 downto 0) + beats_fetched;
                        write_ram_b_in.read_is_requested <= '1';
                        beats_fetched <= beats_fetched + 1;
                    end if;
                else
                    core_write_word   <= beat_now(16*word_in_beat + 15 downto 16*word_in_beat);
                    core_write_strobe <= beat_now(64 + 2*word_in_beat + 1 downto 64 + 2*word_in_beat);
                end if;
                if word_in_beat = 3 then
                    word_in_beat <= 0;
                else
                    word_in_beat <= word_in_beat + 1;
                end if;
            end if;

            -- a transaction done: a write's beats consumed, its burst's response if it was the last
            if core_done and t_write then
                w_consumed <= w_consumed + t_beats;
                if t_last then
                    b_ids(to_integer(b_tail(2 downto 0))) <= t_id;
                    b_tail <= b_tail + 1;
                end if;
            end if;

            if reset_i then
                command_head  <= (others => '0');
                head_progress <= false;
                prepared      <= false;
                b_tail        <= (others => '0');
                meta_tail     <= (others => '0');
                w_consumed    <= (others => '0');
                r_issued      <= (others => '0');
            end if;
        end if;
    end process;

------------------------------------------------------------------------
    -- the core's words into beats, into the read buffer
    packer : process(clock)
    begin
        if rising_edge(clock) then
            read_ram_a_in.write_requested   <= '0';
            read_ram_a_in.read_is_requested <= '0';
            if core_read_valid then
                if packed_words = 3 then
                    packed_words <= 0;
                    read_ram_a_in.address         <= r_stored(7 downto 0);
                    read_ram_a_in.data            <= core_read_word & packed;
                    read_ram_a_in.write_requested <= '1';
                    r_stored <= r_stored + 1;
                else
                    packed(16*packed_words + 15 downto 16*packed_words) <= core_read_word;
                    packed_words <= packed_words + 1;
                end if;
            end if;
            if reset_i then
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
    -- the R channel: beats from the read buffer through a 4 beat queue
    r_valid_i <= out_tail /= out_head;
    r_last_i  <= read_meta(to_integer(meta_head(2 downto 0))).last
                 and beat_in_meta + 1 = read_meta(to_integer(meta_head(2 downto 0))).beats;
    r_valid <= to_std(r_valid_i);
    r_data  <= out_data(to_integer(out_head(1 downto 0)));
    r_id    <= read_meta(to_integer(meta_head(2 downto 0))).id;
    r_resp  <= "00";
    r_last  <= to_std(r_last_i);

    read_channel : process(clock)
        variable in_flight : natural range 0 to 3;
    begin
        if rising_edge(clock) then
            read_ram_b_in.read_is_requested <= '0';
            read_ram_b_in.write_requested   <= '0';

            -- a beat leaves
            if r_valid_i and r_ready = '1' then
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
