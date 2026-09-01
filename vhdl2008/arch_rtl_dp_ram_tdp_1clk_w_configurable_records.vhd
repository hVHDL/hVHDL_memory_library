------------------------------------------------------------------------
-- True-dual-port RAM, single clock, both ports read AND write.
--
-- Same entity / architecture name ("rtl") / 2-cycle read latency /
-- interface as the other dual_port_ram architectures. This one is shaped
-- to match the canonical vendor true-dual-port template (Lattice ECP5
-- Memory Usage Guide, Xilinx UG901, the efinix_ram_templates in this
-- library) so Synplify / Diamond LSE infer ONE coherent DP16KD instead
-- of two disconnected single-port block RAMs.
--
-- The three things that matter for the extractor, per port:
--   1. two processes, one per port, sharing ONE shared variable
--      (a non-protected shared variable -- NVC needs --relaxed for this)
--   2. WRITE-FIRST if/else, not "read-always + write-conditionally" :
--          if we = '1' then
--              ram(addr) := din ;
--              dout_reg  <= din ;        -- write branch forwards din
--          elsif re = '1' then
--              dout_reg  <= ram(addr) ;  -- read branch
--          end if ;
--      i.e. dout_reg is assigned exactly once in each branch, and a
--      same-port write shows the just-written data (write-first mode).
--   3. the read enable is re/we in the if/elsif -- NEVER a read gated by
--      "(re or we)" that then does the write inside it.
--
-- read latency is read_pipeline_delay (2) : output_x_buffer is the EBR
-- output register, ram_x_out.data is a second fabric pipeline stage.
--
-- HARDWARE LIMIT: a DP16KD has NO coherency on a same-address collision.
-- If one port writes address X while the other port accesses X the same
-- cycle, the other port's read data is invalid, and two same-cycle
-- writes to X are undefined. Keep the two ports off the same address on
-- the same cycle, or arbitrate upstream.
------------------------------------------------------------------------

architecture rtl of dual_port_ram is

    signal read_a_pipeline : std_logic_vector(read_pipeline_delay-1 downto 0) := (others => '0');
    signal output_a_buffer : std_logic_vector(ram_a_out.data'range) := (others => '0');

    signal read_b_pipeline : std_logic_vector(read_pipeline_delay-1 downto 0) := (others => '0');
    signal output_b_buffer : std_logic_vector(ram_b_out.data'range) := (others => '0');

    constant ram_init : g_ram_init_values'subtype := g_ram_init_values;
    shared variable ram_contents : g_ram_init_values'subtype := ram_init;

    attribute syn_ramstyle : string;
    attribute syn_ramstyle of ram_contents : variable is "block_ram";

begin
    ram_a_out.data_is_ready <= read_a_pipeline(read_a_pipeline'left);
    ram_b_out.data_is_ready <= read_b_pipeline(read_b_pipeline'left);

    process(clock)
    begin
        if rising_edge(clock) then
            read_a_pipeline <= read_a_pipeline(read_a_pipeline'left-1 downto 0) & ram_a_in.read_is_requested;
            read_b_pipeline <= read_b_pipeline(read_b_pipeline'left-1 downto 0) & ram_b_in.read_is_requested;
        end if;
    end process;

    create_ram_a_port : process(clock)
    begin
        if rising_edge(clock) then

            if ram_a_in.write_requested = '1' then
                ram_contents(to_integer(ram_a_in.address)) := ram_a_in.data;
                output_a_buffer <= ram_a_in.data;
            elsif ram_a_in.read_is_requested = '1' then
                output_a_buffer <= ram_contents(to_integer(ram_a_in.address));
            end if;

            ram_a_out.data <= output_a_buffer;
        end if;
    end process;

    create_ram_b_port : process(clock)
    begin
        if rising_edge(clock) then

            if ram_b_in.write_requested = '1' then
                ram_contents(to_integer(ram_b_in.address)) := ram_b_in.data;
                output_b_buffer <= ram_b_in.data;
            elsif ram_b_in.read_is_requested = '1' then
                output_b_buffer <= ram_contents(to_integer(ram_b_in.address));
            end if;

            ram_b_out.data <= output_b_buffer;
        end if;
    end process;

end rtl;
