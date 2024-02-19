architecture rtl of ram_read_x4_write_x1 is

------------------------------------------------------------------------
    ------------------------------

    signal read_a_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_a_buffer : std_logic_vector(ram_read_a_out.data'range);

    signal read_b_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_b_buffer : std_logic_vector(ram_read_b_out.data'range);

    signal read_c_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_c_buffer : std_logic_vector(ram_read_b_out.data'range);

    signal read_d_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_d_buffer : std_logic_vector(ram_read_b_out.data'range);

    shared variable ram_contents : ram_array := initial_values;

begin
    ram_read_a_out.data_is_ready <= read_a_pipeline(read_a_pipeline'left);
    ram_read_b_out.data_is_ready <= read_b_pipeline(read_b_pipeline'left);
    ram_read_c_out.data_is_ready <= read_c_pipeline(read_c_pipeline'left);
    ram_read_d_out.data_is_ready <= read_d_pipeline(read_d_pipeline'left);

    create_ram_a_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_a_pipeline <= read_a_pipeline(read_a_pipeline'left-1 downto 0) & ram_read_a_in.read_is_requested;
            ram_read_a_out.data <= output_a_buffer;
            if (ram_read_a_in.read_is_requested = '1') or (ram_write_in.write_requested = '1') then
                output_a_buffer <= ram_contents(ram_read_a_in.address);
                if ram_write_in.write_requested = '1' then
                    ram_contents(ram_write_in.address) := ram_write_in.data;
                end if;
            end if;
        end if;
    end process;

    create_ram_b_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_b_pipeline <= read_b_pipeline(read_b_pipeline'left-1 downto 0) & ram_read_b_in.read_is_requested;
            ram_read_b_out.data <= output_b_buffer;
            if (ram_read_b_in.read_is_requested = '1') or (ram_write_in.write_requested = '1') then
                output_b_buffer <= ram_contents(ram_read_b_in.address);
            end if;
        end if;
    end process;

    create_ram_c_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_c_pipeline <= read_c_pipeline(read_c_pipeline'left-1 downto 0) & ram_read_c_in.read_is_requested;
            ram_read_c_out.data <= output_c_buffer;
            if (ram_read_c_in.read_is_requested = '1') or (ram_write_in.write_requested = '1') then
                output_c_buffer <= ram_contents(ram_read_c_in.address);
            end if;
        end if;
    end process;

    create_ram_d_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_d_pipeline <= read_d_pipeline(read_d_pipeline'left-1 downto 0) & ram_read_d_in.read_is_requested;
            ram_read_d_out.data <= output_d_buffer;
            if (ram_read_d_in.read_is_requested = '1') or (ram_write_in.write_requested = '1') then
                output_d_buffer <= ram_contents(ram_read_d_in.address);
            end if;
        end if;
    end process;

end rtl;
