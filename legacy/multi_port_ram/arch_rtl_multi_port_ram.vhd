architecture rtl of multi_port_ram is

    type read_pipeline_array is array (ram_read_in'range) of std_logic_vector(1 downto 0);
    type output_buffer_array is array (ram_read_in'range) of std_logic_vector(ram_read_out(0).data'range);
    signal read_pipeline : read_pipeline_array := (others => (others => '0'));
    signal output_buffer : output_buffer_array := (others => (others => '0'));

    shared variable ram_contents : ram_array := initial_values;

begin

create_multi_port_ram :
for i in ram_read_in'range generate

    ram_read_out(i).data_is_ready <= read_pipeline(i)(read_pipeline(i)'left);

    create_ram_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_pipeline(i) <= read_pipeline(i)(read_pipeline(i)'left-1 downto 0) & ram_read_in(i).read_is_requested;
            ram_read_out(i).data <= output_buffer(i);
            if (ram_read_in(i).read_is_requested = '1') or (ram_write_in.write_requested = '1') then
                output_buffer(i) <= ram_contents(ram_read_in(i).address);
                if ram_write_in.write_requested = '1' then
                    ram_contents(ram_write_in.address) := ram_write_in.data;
                end if;
            end if;
        end if;
    end process;

end generate;

end rtl;
