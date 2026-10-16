library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library vunit_lib;
    context vunit_lib.vunit_context;

    use work.dual_port_ram_pkg.all;

-- simple_dual_port_ram against a model: the init values read back, then random writes and
-- reads (also of the address written in the same clock: the old contents), every read's
-- data_is_ready and data after the read latency, with and without the output register.
entity simple_dual_port_ram_tb is
    generic(runner_cfg : string; g_output_register : boolean := true);
end entity;

architecture sim of simple_dual_port_ram_tb is
    constant depth : natural := 64;
    constant width : natural := 20;
    constant latency : natural := 1 + boolean'pos(g_output_register);

    function init return ram_array is
        variable values : ram_array(0 to depth-1)(width-1 downto 0);
    begin
        for i in values'range loop
            values(i) := std_logic_vector(to_unsigned(1000 + 7*i, width));
        end loop;
        return values;
    end function;
    constant init_values : ram_array(0 to depth-1)(width-1 downto 0) := init;
    constant ram_subtype : dpram_ref_record := create_ref_subtypes(datawidth => width, addresswidth => 6);

    signal clock    : std_logic := '0';
    signal done     : boolean := false;
    signal write_in, read_in : ram_subtype.ram_in'subtype;
    signal read_out : ram_subtype.ram_out'subtype;
begin

    clock <= not clock after 5 ns when not done;

    dut : entity work.simple_dual_port_ram
    generic map(g_dpram_subtype => ram_subtype, g_ram_init_values => init_values,
                g_output_register => g_output_register)
    port map(clock, write_in, read_in, read_out);

    main : process
        type expect_array is array (0 to latency) of std_logic_vector(width-1 downto 0);
        type valid_array is array (0 to latency) of boolean;
        variable model   : ram_array(0 to depth-1)(width-1 downto 0) := init_values;
        variable expect  : expect_array;
        variable valid   : valid_array := (others => false);
        variable seed1, seed2 : positive := 3;
        variable r       : real;
        variable waddr, raddr : natural;
        variable wdata   : std_logic_vector(width-1 downto 0);
        variable do_write, do_read : boolean;
        variable reads, collisions : natural := 0;
    begin
        test_runner_setup(runner, runner_cfg);
        init_ram(write_in);
        init_ram(read_in);
        for cycle in 0 to 5000 loop
            uniform(seed1, seed2, r);
            -- the first depth clocks read the init values in order, no writes
            if cycle < depth then
                do_write := false;
                do_read  := true;
                raddr    := cycle;
            else
                do_write := r < 0.6;
                uniform(seed1, seed2, r);
                do_read  := r < 0.6;
                uniform(seed1, seed2, r);
                raddr    := integer(floor(r * real(depth))) mod depth;
            end if;
            uniform(seed1, seed2, r);
            waddr := integer(floor(r * real(depth))) mod depth;
            uniform(seed1, seed2, r);
            if cycle mod 10 = 0 then
                waddr := raddr;     -- a read of the address written in the same clock
            end if;
            wdata := std_logic_vector(to_unsigned(integer(floor(r * real(2**width - 1))), width));

            init_ram(write_in);
            init_ram(read_in);
            if do_write then
                write_data_to_ram(write_in, waddr, wdata);
            end if;
            if do_read then
                request_data_from_ram(read_in, raddr);
            end if;

            -- the reads requested latency clocks ago are ready after this edge
            expect(1 to latency) := expect(0 to latency-1);
            valid(1 to latency)  := valid(0 to latency-1);
            valid(0)             := do_read;
            if do_read then
                expect(0) := model(raddr);              -- before this clock's write
                reads := reads + 1;
                if do_write and waddr = raddr then
                    collisions := collisions + 1;
                end if;
            end if;
            if do_write then
                model(waddr) := wdata;
            end if;

            wait until rising_edge(clock);
            wait for 1 ns;
            -- valid(latency) is the read requested latency clocks before the one just taken
            check(ram_read_is_ready(read_out) = valid(latency - 1), "data_is_ready");
            if valid(latency - 1) then
                check_equal(get_ram_data(read_out), expect(latency - 1), "the data read");
            end if;
        end loop;
        info(integer'image(reads) & " reads, " & integer'image(collisions) &
             " of the address written in the same clock");
        done <= true;
        test_runner_cleanup(runner);
    end process;

end architecture sim;
