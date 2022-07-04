LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

    use work.ram_read_port_pkg.all;
    use work.ram_write_port_pkg.all;
    use work.ram_configuration_pkg.all;

entity bubblesort_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of bubblesort_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 150;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    type int_array is array (integer range 0 to 7) of integer;
    signal memory : int_array := (1,0, 3,5,7,2,4,6);
    signal sorted_memory : int_array := (7,6,5,4,3,2,1,0);

    function "="
    (
        left, right : int_array
    )
    return boolean
    is
        variable return_value : boolean := true;
    begin
        for i in int_array'range loop
            return_value := return_value and (left(i) = right(i));
        end loop;

        return return_value;
    end "=";

    signal read_port1      : ram_read_port_record  := init_ram_read_port;
    signal ram_write_port1 : ram_write_port_record := init_ram_write_port;

    signal read_port2      : ram_read_port_record  := init_ram_read_port;
    signal ram_write_port2 : ram_write_port_record := init_ram_write_port;

    signal ram_memory : integer_array(0 to lookup_table_size - 1) := (((7,6,5,4,3,2,1,0)),others => 0);

    signal data_from_port1 : integer := 0;
    signal data_from_port2 : integer := 0;

    signal ram_address : integer range 0 to 7 := 1;

    signal swap_requested : boolean := false;
begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(sorted_memory      = (0,1,2,3,4,5,6,7), "sort failed with test vector");
        check(ram_memory(0 to 7) = (0,1,2,3,4,5,6,7), "sort failed with ram sort");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;
------------------------------------------------------------------------

    stimulus : process(simulator_clock)
        variable i, i1 : integer := 0;
        variable j, j1 : integer := 0;

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            create_ram_read_port(read_port1       , ram_memory);
            create_ram_write_port(ram_write_port1 , ram_memory);
            create_ram_read_port(read_port2       , ram_memory);
            create_ram_write_port(ram_write_port2 , ram_memory);

            ------------- test bubble sort in memory ---------
            swap_requested <= false;
            if ram_read_is_ready(read_port1) or simulation_counter = 0 then
                swap_requested <= true;
                ram_address <= (ram_address + 1) mod 7;
                if (ram_address + 1) mod 7 = 0 then
                    ram_address <= 0;
                end if;
                if get_ram_data(read_port1) > get_ram_data(read_port2) then
                    write_data_to_ram(ram_write_port1, ram_address, get_ram_data(read_port2));
                    write_data_to_ram(ram_write_port2, ram_address + 1, get_ram_data(read_port1));
                end if;
            end if;

            if swap_requested then
                request_data_from_ram(read_port1, ram_address);
                request_data_from_ram(read_port2, ram_address + 1);
            end if;
            --------------------------------------------------

            ------------- test with a simple vector ----------
            i  := simulation_counter mod int_array'length;
            i1 := (simulation_counter + 1) mod int_array'length;
            if i1 = 0 then
                i1 := 1;
                i  := 0;
            end if;

            if sorted_memory(i) > sorted_memory(i1) then
                sorted_memory(i1) <= sorted_memory(i);
                sorted_memory(i)  <= sorted_memory(i1);
            end if;
            --------------------------------------------------


        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
