architecture sim of multi_port_ram is

    impure function init_ram
    (
        ram_init_values : ram_array
    )
    return ram_array
    is
        variable retval : ram_array := (others => (others => '0'));
    begin

        for i in ram_init_values'range loop
            retval(i) := ram_init_values(i);
        end loop;

        return retval;
        
    end init_ram;

------------------------------------------------------------------------
    type dp_ram is protected

    ------------------------------
        impure function get_ram_contents return ram_array;
    ------------------------------
        procedure write_ram(
            address : in natural;
            data :    in std_logic_vector);
    ------------------------------
        impure function read_data(address : natural)
            return std_logic_vector;
    ------------------------------

    end protected dp_ram;

------------------------------------------------------------------------
    type dp_ram is protected body
    ------------------------------

        variable ram_contents : ram_array := init_ram(initial_values);

    ------------------------------
        impure function get_ram_contents return ram_array
        is
        begin

            return ram_contents;
            
        end get_ram_contents;
    ------------------------------
        impure function read_data
        (
            address : natural
        )
        return std_logic_vector 
        is
        begin
            return ram_contents(address);
        end read_data;

    ------------------------------
        procedure write_ram
        (
            address : in natural;
            data    : in std_logic_vector
        ) is
        begin
            ram_contents(address) := data;
        end write_ram;


    ------------------------------
    end protected body;
------------------------------------------------------------------------

    shared variable dual_port_ram_array : dp_ram;
    type read_pipeline_array is array (ram_read_in'range) of std_logic_vector(1 downto 0);
    type output_buffer_array is array (ram_read_in'range) of std_logic_vector(ram_read_out(0).data'range);
    signal read_pipeline : read_pipeline_array := (others => (others => '0'));
    signal output_buffer : output_buffer_array := (others => (others => '0'));

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
                    output_buffer(i) <= dual_port_ram_array.read_data(ram_read_in(i).address);
                    if ram_write_in.write_requested = '1' then
                        dual_port_ram_array.write_ram(ram_write_in.address, ram_write_in.data);
                    end if;
                end if;
            end if;
        end process;

end generate;

end sim;
