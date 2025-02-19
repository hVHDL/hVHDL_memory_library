LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity hyperram_io_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of hyperram_io_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 50;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----
    signal cs   : std_logic_vector(1 downto 0) := "11";
    signal cs_counter : natural := 0;


    signal rwds                : std_logic_vector(1 downto 0) := "11";
    signal rwds_counter        : natural                      := 0;
    signal rwds_dir_out_when_1 : std_logic_vector(1 downto 0) := "00";
    signal rwds_dir_counter    : natural                      := 0;

    signal dq0                : std_logic_vector(15 downto 0);
    signal dq1                : std_logic_vector(15 downto 0);
    signal dq_counter        : natural                        := 0;
    signal dq_dir_out_when_1 : std_logic_vector(1 downto 0)   := "00";
    signal dq_dir_counter    : natural                        := 0;

    type bytearray is array(natural range <>) of std_logic_vector(7 downto 0);

    signal transmit_counter : natural := 0;
    type wordarray is array(natural range <>) of std_logic_vector(15 downto 0);
    signal transmit_buffer0 : wordarray(5 downto 0);
    signal transmit_buffer1 : wordarray(5 downto 0);

    signal transmit_state_counter : natural := 0;

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

        procedure create_io_counter(signal counter : inout natural; signal io : out std_logic_vector; dir : std_logic_vector := "11") is
        begin
            if counter > 0 then
                counter <= counter - 1;
            end if;

            if counter = 1 then
                io <= dir;
            end if;

        end create_io_counter;

    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;

            create_io_counter(cs_counter   , cs);

            create_io_counter(rwds_dir_counter , rwds_dir_out_when_1 , "00");
            create_io_counter(dq_dir_counter   , dq_dir_out_when_1   , "00");
            transmit_buffer0 <= transmit_buffer0(transmit_buffer0'left-1 downto 0) & x"0000";
            transmit_buffer1 <= transmit_buffer1(transmit_buffer0'left-1 downto 0) & x"0000";

            CASE transmit_state_counter is
                WHEN 0 =>
                    if rwds_dir_counter = 1 then
                        rwds_dir_counter <= 6;
                        rwds_dir_out_when_1 <= "11";
                        transmit_state_counter <= 2;
                    end if;
                WHEN others => --do nothing
            end CASE;

            CASE simulation_counter is
                WHEN 10 => 
                    cs_counter <= 6;
                    cs <= "00";

                    rwds                <= "00";
                    rwds_dir_counter    <= 6;
                    rwds_dir_out_when_1 <= "00";

                    dq_dir_out_when_1 <= "11";
                    dq_dir_counter    <= 3;
                    transmit_buffer0  <= (x"aaaa", x"bbbb", x"cccc", x"0000", x"0000", x"0000");
                    transmit_buffer1  <= (x"ffff", x"ffff", x"ffff", x"0000", x"ffff", x"ffff");

                WHEN others => -- do nothing
            end CASE;

        end if; -- rising_edge
    end process stimulus;	

    dq0 <= transmit_buffer0(transmit_buffer0'left);
    dq1 <= transmit_buffer1(transmit_buffer0'left);
------------------------------------------------------------------------
    ddr : process(simulator_clock)
    begin
        if rising_edge(simulator_clock) then
        end if; -- rising_edge
        if falling_edge(simulator_clock) then
        end if; -- falling_edge
    end process ddr;	
------------------------------------------------------------------------
end vunit_simulation;
