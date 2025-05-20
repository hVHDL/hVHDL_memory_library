
architecture rtl of dual_port_ram is

------------------------------------------------------------------------
    ------------------------------

    signal read_a_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_a_buffer : std_logic_vector(ram_a_out.data'range);

    signal read_b_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_b_buffer : std_logic_vector(ram_b_out.data'range);

    constant ram_init : ram_array := g_ram_init_values;
    shared variable ram_contents : ram_array := ram_init;

begin
    ram_a_out.data_is_ready <= read_a_pipeline(read_a_pipeline'left);
    ram_b_out.data_is_ready <= read_b_pipeline(read_b_pipeline'left);

    create_ram_a_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_a_pipeline <= read_a_pipeline(read_a_pipeline'left-1 downto 0) & ram_a_in.read_is_requested;
            ram_a_out.data  <= output_a_buffer;
            if (ram_a_in.read_is_requested = '1') or (ram_a_in.write_requested = '1') then
                output_a_buffer <= ram_contents(to_integer(ram_a_in.address));
                if ram_a_in.write_requested = '1' then
                    ram_contents(to_integer(ram_a_in.address)) := ram_a_in.data;
                end if;
            end if;
        end if;
    end process;

    create_ram_b_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_b_pipeline <= read_b_pipeline(read_b_pipeline'left-1 downto 0) & ram_b_in.read_is_requested;
            ram_b_out.data  <= output_b_buffer;
            if (ram_b_in.read_is_requested = '1') or (ram_b_in.write_requested = '1') then
                output_b_buffer <= ram_contents(to_integer(ram_b_in.address));
                if ram_b_in.write_requested = '1' then
                    ram_contents(to_integer(ram_b_in.address)) := ram_b_in.data;
                end if;
            end if;
        end if;
    end process;

end rtl;
