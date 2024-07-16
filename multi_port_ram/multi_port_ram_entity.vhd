library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.multi_port_ram_pkg.all;

entity multi_port_ram is
    generic(number_of_read_ports : natural;
            initial_values : ram_array := (others => (others => '1')));
    port (
        clock        : in std_logic;
        ram_read_in  : in ram_read_in_array(0 to number_of_read_ports-1);
        ram_read_out : out ram_read_out_array(0 to number_of_read_ports-1);
        --------------------
        ram_write_in : in ram_write_in_record
    );
end entity multi_port_ram;

architecture rtl of multi_port_ram is

    use work.ram_port_pkg.all;

    signal ram_a_in : ram_in_array(0 to number_of_read_ports-1);
    signal ram_b_in : ram_in_array(0 to number_of_read_ports-1);
    signal ram_a_out : ram_out_array(0 to number_of_read_ports-1);
    /* signal ram_b_out : ram_out_array(ram_read_out'range); */

begin

    create_multi_port_ram_from_dp_ram:
    for i in ram_read_in'range generate
        ram_a_in(i) <= (address          => ram_read_in(i).address        ,
                       read_is_requested => ram_read_in(i).read_is_requested ,
                       data              => (others => '0')               ,
                       write_requested   => '0');

        ram_b_in(i) <= (address          => ram_write_in.address ,
                       read_is_requested => '0'                  ,
                       data              => ram_write_in.data    ,
                       write_requested   => ram_write_in.write_requested);

        ram_read_out(i) <= (data         => ram_a_out(i).data ,
                           data_is_ready => ram_a_out(i).data_is_ready);

        u_dpram : entity work.dual_port_ram
        generic map(initial_values)
        port map(
        clock ,
        ram_a_in(i)   ,
        ram_a_out(i)  ,
        --------------
        ram_b_in(i)  ,
        open);

    end generate;

end rtl;
