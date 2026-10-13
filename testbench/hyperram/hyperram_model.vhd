library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.hyperram_pkg.all;

-- Behavioural model of a dual die HyperRAM (W959D8NFYA) for simulation.
-- Fixed latency only. Memory is modelled with g_address_bits word addresses per die. A
-- configuration register write applies to both dies (whether the device does so is not
-- known; the controllers here do not depend on it). A burst that crosses from one die to the
-- other is an error.
-- Latency counting follows the same reading of the datasheet as the controller,
-- so it verifies the controller logic, not that interpretation.
entity hyperram_model is
    generic(
        g_address_bits : positive := 12;
        g_tckd         : time := 4 ns;      -- CK to DQ/RWDS valid on reads
        g_tckdi        : time := 4 ns;      -- CK to the previous DQ/RWDS invalid, X until g_tckd
        g_tcsm         : time := 4 us;
        g_stuck_dq_bit : integer := -1;     -- >= 0 forces that DQ bit low on reads, for testing testers
        -- a word on the other die than the burst's first is an error; false for controllers
        -- that keep CK running after a read's last word, whose reads at the top of a die
        -- burst on past it
        g_die_crossing_is_error : boolean := true
    );
    port(
        ck      : in std_logic;
        cs_n    : in std_logic;
        reset_n : in std_logic;
        dq      : inout std_logic_vector(7 downto 0);
        rwds    : inout std_logic
    );
end entity hyperram_model;

architecture behavioural of hyperram_model is

    type memory_array is array (natural range <>) of std_logic_vector(15 downto 0);

    function latency_from_config(cr0 : std_logic_vector(15 downto 0)) return natural is
    begin
        CASE cr0(7 downto 4) is
            WHEN "1110" => return 3;
            WHEN "1111" => return 4;
            WHEN "0000" => return 5;
            WHEN "0001" => return 6;
            WHEN others => return 7;
        end CASE;
    end latency_from_config;

begin

    model : process
        variable memory           : memory_array(0 to 2**(g_address_bits+1)-1) := (others => (others => 'U'));
        variable cr0_value        : std_logic_vector(15 downto 0) := config_register_0_default;
        variable die              : natural range 0 to 1;
        variable ca               : hyperram_header;
        variable edge             : natural;
        variable first_data_edge  : natural;
        variable address          : natural;
        variable word             : std_logic_vector(15 downto 0);
        variable is_read, is_register, is_die1 : boolean;
        variable is_wrapped       : boolean;
        variable wrap_words       : natural;
        variable cs_fall_time     : time;

        -- the memory of the die the burst started on: a word on the other die is an error
        impure function memory_index(word_address : natural) return natural is
            variable a : unsigned(24 downto 0);
        begin
            assert not g_die_crossing_is_error or (word_address / 2**24) mod 2 = die
                report "hyperram model: burst across the die boundary" severity error;
            a := to_unsigned(word_address mod 2**25, 25);
            return to_integer(a(24) & a(g_address_bits-1 downto 0));
        end function;

        procedure next_address is
        begin
            if is_wrapped and not is_register then
                address := address - (address mod wrap_words) + ((address + 1) mod wrap_words);
            else
                address := address + 1;
            end if;
        end procedure;

        impure function register_value(word_address : natural) return std_logic_vector is
            variable a : unsigned(24 downto 0);
        begin
            a := to_unsigned(word_address mod 2**25, 25);
            CASE to_integer(a(23 downto 0)) is
                WHEN id_register_0 =>
                    if a(24) = '1' then return id_register_0_die1; else return id_register_0_die0; end if;
                WHEN id_register_1     => return id_register_1_value;
                WHEN config_register_0 => return cr0_value;
                WHEN config_register_1 => return x"FFC1";
                WHEN others            => return x"XXXX";
            end CASE;
        end function;

    begin
        dq   <= (others => 'Z');
        rwds <= 'Z';

        wait until falling_edge(cs_n);
        assert ck = '0' report "hyperram model: CS# fell while CK high" severity error;
        assert reset_n = '1' report "hyperram model: transaction during reset" severity error;
        cs_fall_time := now;

        -- fixed latency is signalled with RWDS high during CA
        rwds <= '1';
        edge := 0;

        transaction : loop
            wait on ck, cs_n;
            exit transaction when cs_n = '1';
            edge := edge + 1;

            assert now - cs_fall_time <= g_tcsm report "hyperram model: tCSM violated" severity error;

            if edge <= 6 then
                ca(47 - 8*(edge-1) downto 40 - 8*(edge-1)) := dq;
                if edge = 6 then
                    is_read     := ca(47) = '1';
                    is_register := ca(46) = '1';
                    is_wrapped  := ca(45) = '0';
                    -- CR0[1:0] wrapped burst length in bytes: 00 128, 01 64, 10 16, 11 32
                    die := (to_integer(unsigned(ca(44 downto 16)) & unsigned(ca(2 downto 0))) / 2**24) mod 2;
                    CASE cr0_value(1 downto 0) is
                        WHEN "00"   => wrap_words := 64;
                        WHEN "01"   => wrap_words := 32;
                        WHEN "10"   => wrap_words := 8;
                        WHEN others => wrap_words := 16;
                    end CASE;
                    address     := to_integer(unsigned(ca(44 downto 16)) & unsigned(ca(2 downto 0)));
                    if is_register and not is_read then
                        first_data_edge := 7;
                    else
                        first_data_edge := 4*latency_from_config(cr0_value) + 5;
                    end if;
                    if is_read then
                        rwds <= transport '0' after g_tckd;
                    else
                        rwds <= transport 'Z' after g_tckd;
                    end if;
                end if;

            elsif edge >= first_data_edge then
                if is_read then
                    if (edge - first_data_edge) mod 2 = 0 then
                        if is_register then
                            word := register_value(address);
                        else
                            word := memory(memory_index(address));
                        end if;
                        if g_stuck_dq_bit >= 0 then
                            word(g_stuck_dq_bit) := '0';
                            word(g_stuck_dq_bit + 8) := '0';
                        end if;
                        if g_tckdi < g_tckd then
                            dq   <= transport (others => 'X') after g_tckdi;
                            rwds <= transport 'X' after g_tckdi;
                        end if;
                        dq   <= transport word(15 downto 8) after g_tckd;
                        rwds <= transport '1' after g_tckd;
                    else
                        if g_tckdi < g_tckd then
                            dq   <= transport (others => 'X') after g_tckdi;
                            rwds <= transport 'X' after g_tckdi;
                        end if;
                        dq      <= transport word(7 downto 0) after g_tckd;
                        rwds    <= transport '0' after g_tckd;
                        next_address;
                    end if;
                else
                    if (edge - first_data_edge) mod 2 = 0 then
                        word(15 downto 8) := dq;
                        if not is_register and rwds = '1' then
                            word(15 downto 8) := memory(memory_index(address))(15 downto 8);
                        end if;
                    else
                        word(7 downto 0) := dq;
                        if not is_register and rwds = '1' then
                            word(7 downto 0) := memory(memory_index(address))(7 downto 0);
                        end if;
                        if is_register then
                            if (address mod 2**24) = config_register_0 then
                                cr0_value := word;
                            end if;
                        else
                            memory(memory_index(address)) := word;
                        end if;
                        next_address;
                    end if;
                end if;
            end if;
        end loop transaction;

        assert ck = '0' report "hyperram model: CS# rose while CK high" severity error;
        -- outputs still in flight finish, then the bus is released
        dq   <= transport (others => 'Z') after g_tckd;
        rwds <= transport 'Z' after g_tckd;
        wait for g_tckd;
        assert now - cs_fall_time <= g_tcsm report "hyperram model: tCSM violated" severity error;
    end process model;

end architecture behavioural;
