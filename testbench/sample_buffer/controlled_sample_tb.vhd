LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity controlled_sample_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of controlled_sample_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 1500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    package ram_port_pkg is new work.ram_port_generic_pkg 
        generic map(
           g_ram_bit_width => 22
           , g_ram_depth_pow2 => 6);
    use ram_port_pkg.all;

    package sample_trigger_pkg is new work.sample_trigger_generic_pkg generic map(g_ram_depth => ram_depth);
    use sample_trigger_pkg.all;

    signal ram_a_in  : ram_in_record;
    signal ram_a_out : ram_out_record;
    --------------------
    signal ram_b_in  : ram_in_record;
    signal ram_b_out : ram_out_record;


    signal test_output : std_logic_vector(ram_a_out.data'range) := (others => '0');

    signal int_sin : integer := 0;
    signal triggered : std_logic_vector(1 downto 0) := "00";
    signal trigger : boolean := false;
    signal ram_write_enabled : boolean := false;
    signal write_counter : natural range 0 to ram_depth-1;
    -- signal read_counter : natural range 0 to ram_depth-1;

    signal sample_trigger : sample_trigger_record := init_trigger;
    signal write_address: natural range 0 to ram_depth-1 := 0;

    signal counter : natural := 150;

    signal ram_data_requested : boolean := false;

    signal sample_sign : boolean := false;
    signal last_trigger : boolean := false;

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
    sample_sign <= (simulation_counter mod 3) = 0;
    last_trigger <= last_trigger_detected(sample_trigger);

    stimulus : process(simulator_clock)

        variable sample_event : boolean := false;

    begin
        if rising_edge(simulator_clock) then

            simulation_counter <= simulation_counter + 1;

            init_ram(ram_a_in);
            init_ram(ram_b_in);

            sample_event := (simulation_counter mod 3) = 0;
            create_trigger(sample_trigger, trigger_detected => int_sin < -5000, event => sample_event);

            int_sin <= integer(sin(real(simulation_counter)/150.0*2.0*math_pi)*32767.0);

            if sample_event then
                write_data_to_ram(
                    ram_a_in
                    , get_write_address(sample_trigger)
                    , std_logic_vector(to_signed(int_sin , ram_a_in.data'length)) 
                );

            end if;

            CASE simulation_counter is
                WHEN 398 => prime_trigger(sample_trigger, 20);
                WHEN 800 => prime_trigger(sample_trigger, 25); 
                WHEN others => --do nothing
            end CASE;

            if last_trigger_detected(sample_trigger) then
                ram_data_requested <= true;
            end if;

            if ram_data_requested then
                calculate_read_address(sample_trigger);
                request_data_from_ram(ram_b_in, get_sample_address(sample_trigger));
            end if;

            if sample_trigger.read_counter = ram_depth-1 then
                ram_data_requested <= false;
            end if;


        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
    u_dpram : entity work.generic_dual_port_ram
    generic map(ram_port_pkg)
    port map(
    simulator_clock ,
    ram_a_in   ,
    ram_a_out  ,
    --------------
    ram_b_in  ,
    ram_b_out);
------------------------------------------------------------------------
end vunit_simulation;
