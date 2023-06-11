library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package hyperram_driver_pkg is

    type std16_array is array (integer range 2 downto 0) of std_logic_vector(15 downto 0);

    type hyperram_driver_record is record
        cs_n     : std_logic;
        dq       : std_logic_vector(7 downto 0);
        rwds     : std_logic;
        data_out : std_logic_vector(15 downto 0);
        bus_is_out_when_1 : std_logic;
        --
        shift_register   : std16_array;
        transmit_counter : natural;
    end record;
    constant init_hyperram : hyperram_driver_record := ('0',(others => '0'), '0', (others => '0'), '0', (others => (others => '0')), 0);

------------------------------------------------------------------------
    procedure create_hyperram_driver (
        signal self : inout hyperram_driver_record;
        input_data : in std_logic_vector(15 downto 0));
------------------------------------------------------------------------
    procedure request_hyperram_transmit (
        signal self : out hyperram_driver_record;
        data_in : std16_array);

------------------------------------------------------------------------
end package hyperram_driver_pkg;

package body hyperram_driver_pkg is

------------------------------------------------------------------------
    procedure create_hyperram_driver
    (
        signal self : inout hyperram_driver_record;
        input_data : in std_logic_vector(15 downto 0)
    ) is
        variable shift_data : std_logic_vector(15 downto 0);
    begin
        self <= init_hyperram;

        if self.bus_is_out_when_1 = '0' then
            shift_data := (others => '0');
        else
            shift_data := input_data;
        end if;

        self.shift_register <= self.shift_register(self.shift_register'left -1 downto 0) & x"0000";
        if self.transmit_counter > 0 then
            self.transmit_counter <= self.transmit_counter - 1;
        end if;

        if self.transmit_counter > 0 then
            self.bus_is_out_when_1 <= '1';
        end if;
        
    end create_hyperram_driver;

------------------------------------------------------------------------
    procedure request_hyperram_transmit
    (
        signal self : out hyperram_driver_record;
        data_in : std16_array
    ) is
    begin
        self.shift_register    <= data_in;
        self.bus_is_out_when_1 <= '1';
        self.transmit_counter  <= 2;
        
    end request_hyperram_transmit;
------------------------------------------------------------------------
end package body hyperram_driver_pkg;
------------------------------------------------------------------------
LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

    use work.hyperram_driver_pkg.all;

entity hyperram_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of hyperram_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----
    signal hyperram_driver : hyperram_driver_record := init_hyperram;
    signal input_register : std16_array := (others => (others => '0'));

    constant test_data : std16_array := (x"acdc", x"0110", x"abcd");
    signal test_data_has_been_received : boolean := false;

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(test_data_has_been_received, "testdata was not received");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;
------------------------------------------------------------------------

    stimulus : process(simulator_clock)

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            create_hyperram_driver(hyperram_driver, x"ffff");

            case simulation_counter is
                when 5 => request_hyperram_transmit(hyperram_driver, test_data);
                when others => --do nothing
            end case;

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
    hyperram_model : process(simulator_clock)
    begin
        if rising_edge(simulator_clock) then
            if hyperram_driver.bus_is_out_when_1 = '1' then
                input_register <= input_register(input_register'left-1 downto 0) & hyperram_driver.shift_register(hyperram_driver.shift_register'left);
            end if;
            if input_register = test_data then
                test_data_has_been_received <= true;
            end if;

        end if; --rising_edge
    end process hyperram_model;	
------------------------------------------------------------------------
end vunit_simulation;
