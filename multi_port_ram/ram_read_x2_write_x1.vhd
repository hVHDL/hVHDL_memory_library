library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.multi_port_ram_pkg.all;

entity ram_read_2x_write_1x is
    generic(initial_values : ram_array := (others => (others => '1')));
    port (
        clock          : in std_logic;
        ram_read_a_in  : in ram_read_in_record;
        ram_read_a_out : out ram_read_out_record;
        --------------------
        ram_read_b_in  : in ram_read_in_record;
        ram_read_b_out : out ram_read_out_record;
        --------------------
        ram_write_in   : in ram_write_in_record
    );
end entity ram_read_2x_write_1x;
