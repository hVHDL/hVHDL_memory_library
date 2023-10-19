
architecture sim of dual_port_ram is

------------------------------------------------------------------------
    type dp_ram is protected

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

        variable ram_contents : ram_array := init_ram(initial_values);

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

    signal read_a_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_a_buffer : std_logic_vector(ram_read_a_out.data'range);

    signal read_b_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_b_buffer : std_logic_vector(ram_read_b_out.data'range);

begin
    ram_read_a_out.data_is_ready <= read_a_pipeline(read_a_pipeline'left);
    ram_read_b_out.data_is_ready <= read_b_pipeline(read_a_pipeline'left);

    create_ram_a_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_a_pipeline <= read_a_pipeline(read_a_pipeline'left-1 downto 0) & ram_read_a_in.read_is_requested;
            ram_read_a_out.data <= output_a_buffer;
            if (ram_read_a_in.read_is_requested = '1') or (ram_write_a_in.write_requested = '1') then
                output_a_buffer <= dual_port_ram_array.read_data(ram_read_a_in.address);
                if ram_write_a_in.write_requested = '1' then
                    dual_port_ram_array.write_ram(ram_write_a_in.address, ram_write_a_in.data);
                end if;
            end if;
        end if;
    end process;

    create_ram_b_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_b_pipeline <= read_b_pipeline(read_b_pipeline'left-1 downto 0) & ram_read_b_in.read_is_requested;
            ram_read_b_out.data <= output_b_buffer;
            if (ram_read_b_in.read_is_requested = '1') or (ram_write_b_in.write_requested = '1') then
                output_b_buffer <= dual_port_ram_array.read_data(ram_read_b_in.address);
                if ram_write_b_in.write_requested = '1' then
                    dual_port_ram_array.write_ram(ram_write_b_in.address, ram_write_b_in.data);
                end if;
            end if;
        end if;
    end process;

end sim;
