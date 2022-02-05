LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
    use vunit_lib.run_pkg.all;

entity tb_hyperram is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of tb_hyperram is

    signal simulation_running : boolean;
    signal simulator_clock : std_logic;
    constant clock_per : time := 1 ns;
    constant clock_half_per : time := 0.5 ns;
    constant simtime_in_clocks : integer := 50;

    signal simulation_counter : natural := 0;
    -----------------------------------
    -- simulation specific signals ----
    procedure shift_and_register
    (
        signal shift_register : inout std_logic_vector;
        data_to_be_shifted_in : in std_logic_vector
    ) is
    begin

        shift_register <= shift_register(shift_register'left-data_to_be_shifted_in'high -1 downto 0) & data_to_be_shifted_in;
        
    end shift_and_register;

    signal shift_register_1 : std_logic_vector(47 downto 0) := (others => '0'); 

    constant testi : std_logic_vector(7 downto 0) := x"aa";

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        simulation_running <= true;
        wait for simtime_in_clocks*clock_per;
        simulation_running <= false;
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

------------------------------------------------------------------------
    sim_clock_gen : process
    begin
        simulator_clock <= '0';
        wait for clock_half_per;
        while simulation_running loop
            wait for clock_half_per;
                simulator_clock <= not simulator_clock;
            end loop;
        wait;
    end process;
------------------------------------------------------------------------

    stimulus : process(simulator_clock)

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            shift_and_register(shift_register_1, x"ab");

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
