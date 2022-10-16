LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity command_frames_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of command_frames_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 50;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    type hyperram_data_array is array (integer range 0 to 2) of std_logic_vector(15 downto 0);
    signal hyperram_shift_register : hyperram_data_array := (others =>(others => '0'));

    signal hyperram_output : std_logic_vector(15 downto 0) := (others => '0');

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

            hyperram_output <= hyperram_shift_register(0);
            hyperram_shift_register <= hyperram_shift_register(0 to 1) & x"0000";

            if simulation_counter = 5 then
                hyperram_shift_register <= (
                                               (15 => '1', 14 => '1', 13 => '0', 12 downto 0 => '1'),
                                               (others => '0'),
                                               (0=> '1', others => '0')
                                           );
            end if;


        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
