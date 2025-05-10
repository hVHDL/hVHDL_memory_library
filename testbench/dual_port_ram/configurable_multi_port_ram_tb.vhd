LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity generic_multi_port_ram_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of generic_multi_port_ram_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 1500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----

    use work.multi_port_ram_pkg.all;


    constant ref_subtype : subtype_ref_record := create_ref_subtypes(readports => 5);

    -- signal ram_read_in  : ram_read_in_array(0 to 4)(address(address_rangeref'range));
    -- signal ram_read_out : ram_read_out_array(ram_read_in'range)(data(data_rangeref'range));
    -- signal ram_write_in : ram_write_in_record(address(address_rangeref'range), data(data_rangeref'range));

    signal ram_read_in  : ref_subtype.ram_read_in'subtype;
    signal ram_read_out : ref_subtype.ram_read_out'subtype;
    signal ram_write_in : ref_subtype.ram_write_in'subtype;
    constant init_values : work.dual_port_ram_pkg.ram_array(0 to 2**10)(ref_subtype.data'range) := (others => (others => '0'));

    signal read_counter : natural := 9;
    signal ready_counter : natural := 0;

    signal ram_was_read : boolean := false;

    signal test_output : std_logic_vector(ram_read_out(0).data'range) := (others => '0');

    signal output_is_correct       : boolean := false;
    signal last_ram_index_was_read : boolean := false;

    signal testi : ram_read_in_array_of_arrays(0 to 5)(0 to 4)(address(15 downto 0));
    signal toinen_testi : ram_read_in_array_of_arrays(testi'range)(testi(testi'low)'range)(address(15 downto 0));

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(ram_was_read);
        -- check(last_ram_index_was_read, "last index was not read");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;

------------------------------------------------------------------------

    stimulus : process(simulator_clock)
        constant read_offset : natural := 57;
        constant read_pipeline_delay : natural := 2;
    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;
            init_mp_ram(ram_read_in , ram_write_in);

            if simulation_counter < 51
            then
                write_data_to_ram(ram_write_in, simulation_counter, uint_to_slv(simulation_counter, ref_subtype.data));
            end if;

            if simulation_counter >= read_offset
                and simulation_counter < 50+read_offset
            then
                request_data_from_ram(ram_read_in(0), simulation_counter-read_offset + 1);
                request_data_from_ram(ram_read_in(1), simulation_counter-read_offset + 1);
                request_data_from_ram(ram_read_in(2), simulation_counter-read_offset + 1);
                request_data_from_ram(ram_read_in(3), simulation_counter-read_offset + 1);
                request_data_from_ram(ram_read_in(4), simulation_counter-read_offset + 1);
            end if;

            if ram_read_is_ready(ram_read_out(0)) then
                check(get_ram_data(ram_read_out(0)) = uint_to_slv(simulation_counter-read_offset-read_pipeline_delay, ref_subtype.data));
                check(get_ram_data(ram_read_out(1)) = uint_to_slv(simulation_counter-read_offset-read_pipeline_delay, ref_subtype.data));
                check(get_ram_data(ram_read_out(2)) = uint_to_slv(simulation_counter-read_offset-read_pipeline_delay, ref_subtype.data));
                check(get_ram_data(ram_read_out(3)) = uint_to_slv(simulation_counter-read_offset-read_pipeline_delay, ref_subtype.data));
                check(get_ram_data(ram_read_out(4)) = uint_to_slv(simulation_counter-read_offset-read_pipeline_delay, ref_subtype.data));
            end if;

            ram_was_read <= ram_was_read or ram_read_is_ready(ram_read_out(0));


        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
    u_mpram : entity work.multi_port_ram
    generic map(init_values)
    port map(
        clock => simulator_clock
        ,ram_read_in => ram_read_in
        ,ram_read_out => ram_read_out
        ,ram_write_in => ram_write_in);

------------------------------------------------------------------------
end vunit_simulation;
