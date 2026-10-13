LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

    use work.ram_read_port_pkg.all;
    use work.ram_write_port_pkg.all;
    use work.ram_configuration_pkg.all;

entity dual_port_ram_interface_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of dual_port_ram_interface_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 50;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    signal read_port1      : ram_read_port_record  := init_ram_read_port;
    signal ram_write_port1 : ram_write_port_record := init_ram_write_port;

    signal read_port2      : ram_read_port_record  := init_ram_read_port;
    signal ram_write_port2 : ram_write_port_record := init_ram_write_port;

    signal data_from_ram : integer :=0;
    signal ram_read_counter : integer := 7;
    signal delay_counter : integer := 0;

    signal ram_memory : integer_array(0 to lookup_table_size - 1) := init_ram_data_with_indices;

    signal data_from_ram1 : integer;

    signal ready_counter : integer := 0;
    signal ram_was_read : boolean := false;

    signal ram_write_counter : integer := 0;

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(ram_was_read, "ram was never read");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;
------------------------------------------------------------------------

    stimulus : process(simulator_clock)

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            create_ram_read_port(read_port1       , ram_memory);
            create_ram_write_port(ram_write_port1 , ram_memory);

            if delay_counter > 0 then
                delay_counter <= delay_counter -1 ;
            end if;

            if ram_write_counter = 4 then
                ram_read_counter <= 0;
            end if;

            if ram_write_counter < 50 then
                ram_write_counter <= ram_write_counter + 1;
                write_data_to_ram(ram_write_port1, ram_write_counter, 11000);
            end if;

            CASE ram_read_counter is
                WHEN 0 => request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                WHEN 1 => request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                WHEN 2 => request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                          delay_counter <= 5;
                WHEN 3 => 
                    if delay_counter = 1 then
                        request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                    end if;
                WHEN 4 => request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                WHEN 5 => request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                WHEN 6 => request_data_from_ram_and_increment(ram_read_counter, read_port1, ram_read_counter);
                WHEN others => -- do nothing
            end CASE;

            if ram_read_is_ready(read_port1) then
                check(get_ram_data(read_port1) = 11000, "expected 11000, got " & integer'image(get_ram_data(read_port1)));
                data_from_ram1 <= get_ram_data(read_port1);
                ready_counter  <= (ready_counter + 1);
                ram_was_read   <= true;
            end if;

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
