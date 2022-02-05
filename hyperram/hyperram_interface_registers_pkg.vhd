library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package hyperram_interface_registers_pkg is

    type hyperram_header_record is record
        transaction_type_1_read_0_write          : std_logic_vector(47 downto 47);
        select_memory_with_1_and_register_with_0 : std_logic_vector(46 downto 46);
        linear_burst_with_0_wrapped_with_1       : std_logic_vector(45 downto 45);
        row_and_upper_column_address             : std_logic_vector(44 downto 16);
        reserved                                 : std_logic_vector(15 downto 3);
        lower_column_address                     : std_logic_vector(2 downto 0);
    end record;

end package hyperram_interface_registers_pkg;

package body hyperram_interface_registers_pkg is

end package body hyperram_interface_registers_pkg;

