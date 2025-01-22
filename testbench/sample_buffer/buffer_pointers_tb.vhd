

LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity buffer_pointers_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of buffer_pointers_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 1500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    package ram_port_pkg is new work.ram_port_generic_pkg generic map(g_ram_bit_width => 20, g_ram_depth_pow2 => 7);
    use ram_port_pkg.all;

    signal int_sin : integer := 0;
    signal triggered : boolean := false;
    signal ram_write_enabled : boolean := false;
    signal write_counter : natural range 0 to ram_depth-1;
    signal sample_requested : boolean := false;
    signal write_after_triggered : natural := ram_depth-1;
    -- signal read_counter : natural range 0 to ram_depth-1;

    signal trigger_enabled : boolean := false;

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        -- check(ram_was_read);
        -- check(last_ram_index_was_read, "last index was not read");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;

------------------------------------------------------------------------

    stimulus : process(simulator_clock)
    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            if write_after_triggered > 0 then
                if write_counter < ram_depth-1  then
                    write_counter <= write_counter + 1;
                else
                    write_counter <= 0;
                end if;
            end if;

            trigger_enabled <= trigger_enabled or simulation_counter = 550;

            if trigger_enabled then
                if write_after_triggered > 0 then
                    write_after_triggered <= write_after_triggered - 1;
                end if;
            end if;

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
