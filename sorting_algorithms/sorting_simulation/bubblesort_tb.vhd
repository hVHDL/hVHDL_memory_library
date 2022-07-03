LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity bubblesort_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of bubblesort_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 50;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    type int_array is array (integer range 0 to 7) of integer;
    signal memory : int_array := (1,0, 3,5,7,2,4,6);
    signal sorted_memory : int_array := (1,0, 3,5,7,2,4,6);

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

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(sorted_memory = (0,1,2,3,4,5,6,7), "sort failed");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;
------------------------------------------------------------------------

    stimulus : process(simulator_clock)
        variable i, i1 : integer := 0;

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

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
        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
