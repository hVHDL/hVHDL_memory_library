------------------------------------------------------------------------
-- Single-process variant of arch_rtl_dp_ram_w_configurable_records.vhd.
--
-- Same entity, same architecture name ("rtl"), same 2-cycle read latency
-- (output_x_buffer -> ram_x_out.data) and the same per-port
-- read-before-write behaviour as the original and as
-- arch_sim_dp_ram_w_configurable_records.vhd. The ONLY change is that
-- both ports are driven from ONE clocked process against a process
-- variable, instead of two processes against a shared variable.
--
-- Why: on Lattice Diamond / Synplify Pro the two-process shared-variable
-- form is inferred as TWO disconnected single-port block RAMs -- each
-- port writes and reads only its own copy, so a write on one port is
-- invisible to a read on the other, and each copy just holds its init
-- contents on the port that never receives writes. A single process with
-- deterministic statement ordering is inferred as one coherent block RAM
-- where a write on either port is seen by a read on the other.
--
-- Read/write behaviour, per port: the read is evaluated before the write
-- in source order, so a read of an address being written on the SAME
-- port the same cycle returns the OLD contents (read-before-write).
--
-- Cross-port collision: with one process a same-cycle same-address
-- access resolves as "port a writes, then port b reads the new value"
-- (source order). Keep the two ports off the same address on the same
-- cycle -- true-dual-port EBR hardware leaves collision reads undefined
-- anyway.
------------------------------------------------------------------------

architecture rtl of dual_port_ram is

    signal read_a_pipeline : std_logic_vector(read_pipeline_delay-1 downto 0) := (others => '0');
    signal output_a_buffer : std_logic_vector(ram_a_out.data'range);

    signal read_b_pipeline : std_logic_vector(read_pipeline_delay-1 downto 0) := (others => '0');
    signal output_b_buffer : std_logic_vector(ram_b_out.data'range);

    constant ram_init : g_ram_init_values'subtype := g_ram_init_values;

begin
    ram_a_out.data_is_ready <= read_a_pipeline(read_a_pipeline'left);
    ram_b_out.data_is_ready <= read_b_pipeline(read_b_pipeline'left);

    create_ram : process(clock)
        variable ram_contents : g_ram_init_values'subtype := ram_init;
    begin
        if rising_edge(clock) then

            read_a_pipeline <= read_a_pipeline(read_a_pipeline'left-1 downto 0) & ram_a_in.read_is_requested;
            read_b_pipeline <= read_b_pipeline(read_b_pipeline'left-1 downto 0) & ram_b_in.read_is_requested;

            ram_a_out.data <= output_a_buffer;
            ram_b_out.data <= output_b_buffer;

            -- port a : read evaluated before the write  ==>  read-before-write
            if (ram_a_in.read_is_requested = '1') or (ram_a_in.write_requested = '1') then
                output_a_buffer <= ram_contents(to_integer(ram_a_in.address));
                if ram_a_in.write_requested = '1' then
                    ram_contents(to_integer(ram_a_in.address)) := ram_a_in.data;
                end if;
            end if;

            -- port b : same
            if (ram_b_in.read_is_requested = '1') or (ram_b_in.write_requested = '1') then
                output_b_buffer <= ram_contents(to_integer(ram_b_in.address));
                if ram_b_in.write_requested = '1' then
                    ram_contents(to_integer(ram_b_in.address)) := ram_b_in.data;
                end if;
            end if;

        end if;
    end process;

end rtl;
