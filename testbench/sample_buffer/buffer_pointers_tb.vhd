LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 

package sample_trigger_generic_pkg is
    generic (g_ram_depth : positive);

    type sample_trigger_record is record
        trigger_enabled       : boolean ;
        triggered             : boolean;
        ram_write_enabled     : boolean;
        write_counter         : natural range 0 to g_ram_depth-1;
        sample_requested      : boolean;
        write_after_triggered : natural range 0 to g_ram_depth-1;
    end record;

    constant init_trigger : sample_trigger_record := (false,false, false, 0, false, g_ram_depth-1);

    procedure create_trigger(signal self : inout sample_trigger_record; trigger_detected : in boolean);
    procedure prime_trigger(signal self : inout sample_trigger_record; samples_after_trigger : natural);

end package sample_trigger_generic_pkg;

package body sample_trigger_generic_pkg is

    procedure create_trigger(signal self : inout sample_trigger_record; trigger_detected : in boolean) is
    begin
        if self.write_after_triggered > 0 then
            if self.write_counter < g_ram_depth-1  then
                self.write_counter <= self.write_counter + 1;
            else
                self.write_counter <= 0;
            end if;
        end if;

        self.triggered <= (self.triggered or trigger_detected) and self.trigger_enabled;

        if self.triggered then
            if self.write_after_triggered > 0 then
                self.write_after_triggered <= self.write_after_triggered - 1;
            else
                self.trigger_enabled <= false;
            end if;
        end if;
    end create_trigger;

    procedure prime_trigger(signal self : inout sample_trigger_record; samples_after_trigger : natural) is
    begin
        if not self.trigger_enabled then
            self.trigger_enabled <= true;
            self.write_after_triggered <= samples_after_trigger;
        end if;
    end prime_trigger;

end package body sample_trigger_generic_pkg;


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

    package ram_port_pkg is new work.ram_port_generic_pkg generic map(g_ram_bit_width => 20, g_ram_depth_pow2 => 7);
    use ram_port_pkg.all;

    package sample_trigger_pkg is new work.sample_trigger_generic_pkg generic map(g_ram_depth => ram_depth);
    use sample_trigger_pkg.all;



    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 1500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----


    signal int_sin : integer := 0;
    signal triggered : boolean := false;
    signal ram_write_enabled : boolean := false;
    signal write_counter : natural range 0 to ram_depth-1;
    signal sample_requested : boolean := false;
    signal write_after_triggered : natural := ram_depth-1;
    -- signal read_counter : natural range 0 to ram_depth-1;

    signal trigger : sample_trigger_record := init_trigger;

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

    write_counter <= trigger.write_counter;
    write_after_triggered <= trigger.write_after_triggered;

    stimulus : process(simulator_clock)

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            create_trigger(trigger, simulation_counter mod 230 = 0);

            CASE simulation_counter is
                WHEN 400 => prime_trigger(trigger, 90);
                WHEN others => --do nothing
            end CASE;

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
end vunit_simulation;
