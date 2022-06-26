LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

    use work.ram_read_port_pkg.all;

entity ram_read_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of ram_read_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 50;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    signal ram1 : ram_read_port_record := init_ram_read_port;
    signal data_from_ram1 : integer :=0;
    signal ram_request_counter : integer range 0 to 7 := 0;
    signal ram_read_counter : integer := 0;
    signal delay_counter : integer := 0;

    signal ram_write_counter : integer range 0 to 7 := 7;

    constant ram_memory : integer_array := sine_table_entries;
    constant ram_test_indices : integer_array(0 to 7) := (5, 25, 55, 101, 3, 457, 9, 15);

    signal ready_counter : integer := 0;

    signal ram_was_read : boolean := false;


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

            create_dual_port_ram(ram1, ram_memory);

            if delay_counter > 0 then
                delay_counter <= delay_counter -1 ;
            end if;

            CASE ram_read_counter is
                WHEN 0 => request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(0));
                WHEN 1 => request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(1));
                WHEN 2 => request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(2));
                          delay_counter <= 5;
                WHEN 3 => 
                    if delay_counter = 1 then
                        request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(3));
                    end if;
                WHEN 4 => request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(4));
                WHEN 5 => request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(5));
                WHEN 6 => request_data_from_ram_and_increment(ram_read_counter, ram1, ram_test_indices(6));
                WHEN 7 => -- do nothing
                WHEN others => -- do nothing
            end CASE;

            if ram_read_is_ready(ram1) then
                data_from_ram1 <= get_ram_data(ram1);
                check(get_ram_data(ram1) = ram_test_indices(ready_counter mod 7), "should be same");
                ready_counter <= (ready_counter + 1) mod 7;
                ram_was_read <= true;
            end if;

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
