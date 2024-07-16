library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.multi_port_ram_pkg.all;

entity multi_port_ram is
    generic(number_of_read_ports : natural;
            initial_values : ram_array := (others => (others => '1')));
    port (
        clock        : in std_logic;
        ram_read_in  : in ram_read_in_array;
        ram_read_out : out ram_read_out_array;
        --------------------
        ram_write_in : in ram_write_in_record
    );
end entity multi_port_ram;

