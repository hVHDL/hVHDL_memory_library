LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
    use vunit_lib.run_pkg.all;

    use work.fpga_dual_port_ram_pkg.all;

entity dual_port_ram_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of dual_port_ram_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 50;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    signal ram1 : ram_record := init_dual_port_ram;
    signal data_from_ram1 : integer :=0;
    signal ram_request_counter : integer range 0 to 7 := 0;
    signal ram_read_counter : integer range 0 to 7 := 0;
    signal delay_counter : integer := 0;


begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;
------------------------------------------------------------------------

    stimulus : process(simulator_clock)

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            create_dual_port_ram(ram1);

            if delay_counter > 0 then
                delay_counter <= delay_counter -1 ;
            end if;

            CASE ram_read_counter is
                WHEN 0 => request_data_from_ram_and_increment(ram_read_counter, ram1, 5);
                WHEN 1 => request_data_from_ram_and_increment(ram_read_counter, ram1, 6);
                WHEN 2 => request_data_from_ram_and_increment(ram_read_counter, ram1, 7);
                          delay_counter <= 5;
                WHEN 3 => 
                    if delay_counter = 1 then
                        request_data_from_ram_and_increment(ram_read_counter, ram1, 8);
                    end if;
                WHEN 4 => request_data_from_ram_and_increment(ram_read_counter, ram1, 9);
                WHEN 5 => request_data_from_ram_and_increment(ram_read_counter, ram1, 10);
                WHEN 6 => request_data_from_ram_and_increment(ram_read_counter, ram1, 11);
                WHEN 7 => -- do nothing
            end CASE;

            if ram_is_ready(ram1) then
                data_from_ram1 <= get_ram_data(ram1);
            end if;


        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
