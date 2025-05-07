
LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity configurable_dual_port_ram_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of configurable_dual_port_ram_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 1500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----
    use work.dual_port_ram_pkg.all;

    constant init_values : ram_array(0 to 159)(15 downto 0) := (others => (others => '0'));

    signal ram_a_in  : ram_in_record(address(0 to 9), data(init_values(0)'range));
    signal ram_a_out : ram_out_record(data(ram_a_in.data'range));
    --------------------
    signal ram_b_in  : ram_a_in'subtype;
    signal ram_b_out : ram_a_out'subtype;

    signal read_counter  : natural := init_values'length;
    signal ready_counter : natural := 0;

    signal ram_was_read : boolean := false;

    signal test_output : std_logic_vector(ram_a_out.data'range) := (others => '0');

    signal output_is_correct       : boolean := false;
    signal last_ram_index_was_read : boolean := false;

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(ram_was_read);
        check(last_ram_index_was_read, "last index was not read");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;

------------------------------------------------------------------------

    stimulus : process(simulator_clock)
    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;
            init_ram(ram_a_in);
            init_ram(ram_b_in);

            if simulation_counter < init_values'length/2 then
                write_data_to_ram(ram_a_in, simulation_counter*2, std_logic_vector(to_unsigned(simulation_counter*2, ram_a_in.data'length)));
                write_data_to_ram(ram_b_in, simulation_counter*2+1, std_logic_vector(to_unsigned(simulation_counter*2+1, ram_a_in.data'length)));
            end if;

            if simulation_counter = init_values'length/2 then
                read_counter <= 0;
            end if;

            if read_counter < init_values'length/2 then
                read_counter <= read_counter + 1;
                request_data_from_ram(ram_a_in, read_counter*2);
                request_data_from_ram(ram_b_in, read_counter*2+1);
            end if;

            if ram_read_is_ready(ram_a_out) then
                ready_counter           <= ready_counter + 1;
                test_output             <= get_ram_data(ram_a_out);
                output_is_correct       <= (get_ram_data(ram_a_out) = std_logic_vector(to_unsigned(ready_counter*2, ram_a_out.data'length)));
                last_ram_index_was_read <= to_integer(unsigned(get_ram_data(ram_b_out))) = init_values'high;

                check(get_ram_data(ram_a_out) = std_logic_vector(to_unsigned(ready_counter*2   , ram_a_out.data'length)));
                check(get_ram_data(ram_b_out) = std_logic_vector(to_unsigned(ready_counter*2+1 , ram_b_out.data'length)));
            end if;
            ram_was_read <= ram_was_read or ram_read_is_ready(ram_a_out);

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
    u_dpram : entity work.dual_port_ram
    generic map(init_values)
    port map(
    simulator_clock ,
    ram_a_in   ,
    ram_a_out  ,
    --------------
    ram_b_in  ,
    ram_b_out);
    
------------------------------------------------------------------------
end vunit_simulation;
