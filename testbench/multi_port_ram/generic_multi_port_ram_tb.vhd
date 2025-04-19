
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity multi_port_ram is
    generic(package mp_ram_port_pkg is new work.generic_multi_port_ram_pkg generic map(<>)
            ;initial_values : mp_ram_port_pkg.ram_array := (others => (others => '1')));
    port (
        clock         : in std_logic
        ;ram_read_in  : in mp_ram_port_pkg.ram_read_in_array
        ;ram_read_out : out mp_ram_port_pkg.ram_read_out_array
        --------------------
        ;ram_write_in  : in mp_ram_port_pkg.ram_write_in_record
    );
    use mp_ram_port_pkg.all;
end entity multi_port_ram;
---
architecture rtl of multi_port_ram is

    package ram_port_pkg is new work.ram_port_generic_pkg 
        generic map( 
                    g_ram_bit_width => ram_bit_width
                    ,g_ram_depth_pow2 => 9);
    use ram_port_pkg.all;

    signal ram_a_in  : ram_in_array  (ram_read_in'range) ;
    signal ram_a_out : ram_out_array (ram_read_in'range) ;
    signal ram_b_in  : ram_in_array  (ram_read_in'range) ;
    signal ram_b_out : ram_out_array (ram_read_in'range) ;

begin

    create_rams :
    for i in ram_read_in'range generate
        u_dpram : entity work.generic_dual_port_ram
        generic map(ram_port_pkg)
        port map(
        clock ,
        ram_a_in(i)     ,
        ram_a_out(i)    ,
        --------------
        ram_b_in(i)  ,
        open);

        ram_a_in(i) <= (
            address            => ram_read_in(i).address
            ,read_is_requested => ram_read_in(i).read_requested
            ,data              => (others => '0')
            ,write_requested   => '0');

        ram_read_out(i) <= (
            data => ram_a_out(i).data
            ,data_is_ready => ram_a_out(i).data_is_ready);

        ram_b_in(i) <= (
            address            => ram_write_in.address
            ,read_is_requested => '0'
            ,data              => ram_write_in.data
            ,write_requested   => ram_write_in.write_requested);
    end generate;

end rtl;

----
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

    package mp_ram_pkg is new work.generic_multi_port_ram_pkg generic map(g_ram_bit_width => 20, g_ram_depth_pow2 => 9);
    use mp_ram_pkg.all;

    signal ram_read_in : ram_read_in_array(0 to 3);
    signal ram_read_out : ram_read_out_array(ram_read_in'range);
    signal ram_write_in : ram_write_in_record;

    signal read_counter : natural := mp_ram_pkg.ram_array'length;
    signal ready_counter : natural := 0;

    signal ram_was_read : boolean := false;

    signal test_output : std_logic_vector(ram_read_out(0).data'range) := (others => '0');

    signal output_is_correct : boolean := false;
    signal last_ram_index_was_read : boolean := false;

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
            init_mp_ram(ram_read_in , ram_write_in);

            if simulation_counter < 51
            then
                write_data_to_ram(ram_write_in, simulation_counter, uint_to_slv(simulation_counter));
            end if;

            if simulation_counter > 1
                and simulation_counter < 52
            then
                request_data_from_ram(ram_read_in(0), simulation_counter-1);
                request_data_from_ram(ram_read_in(1), simulation_counter-1);
                request_data_from_ram(ram_read_in(2), simulation_counter-1);
                request_data_from_ram(ram_read_in(3), simulation_counter-1);
            end if;

            if ram_read_is_ready(ram_read_out(0)) then
                check(get_ram_data(ram_read_out(0)) = uint_to_slv(simulation_counter-4));
                check(get_ram_data(ram_read_out(1)) = uint_to_slv(simulation_counter-4));
                check(get_ram_data(ram_read_out(2)) = uint_to_slv(simulation_counter-4));
                check(get_ram_data(ram_read_out(3)) = uint_to_slv(simulation_counter-4));
            end if;


        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
    u_mpram : entity work.multi_port_ram
    generic map(mp_ram_pkg)
    port map(
        clock => simulator_clock
        ,ram_read_in => ram_read_in
        ,ram_read_out => ram_read_out
        ,ram_write_in => ram_write_in);

------------------------------------------------------------------------
end vunit_simulation;
