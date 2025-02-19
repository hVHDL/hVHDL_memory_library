
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package hyperram_interface_pkg is

    type hyperram_shift_array is array (integer range 0 to 2) of std_logic_vector(15 downto 0);

    subtype hyperram_header is std_logic_vector(47 downto 0);

    subtype transaction_type_1_read_0_write          is std_logic_vector(47 downto 47);
    subtype select_memory_with_1_and_register_with_0 is std_logic_vector(46 downto 46);
    subtype linear_burst_with_0_wrapped_with_1       is std_logic_vector(45 downto 45);
    subtype row_and_upper_column_address             is std_logic_vector(44 downto 16);
    subtype reserved                                 is std_logic_vector(15 downto 3);
    subtype lower_column_address                     is std_logic_vector(2 downto 0);

    function to_std_logic ( number : integer; size : integer)
        return std_logic_vector ;

    function read_data_from_hyperram_memory ( start_address : integer)
        return std_logic_vector;

    function write_data_to_hyperram (
        start_address       : integer;
        number_of_registers : integer)
        return std_logic_vector;

    function to_shift_array ( hyperram_header : std_logic_vector(47 downto 0))
        return hyperram_shift_array;

end package hyperram_interface_pkg;

package body hyperram_interface_pkg is

    function to_std_logic
    (
        number : integer;
        size : integer
    )
    return std_logic_vector 
    is
    begin
        return std_logic_vector(to_unsigned(number, size));
        
    end to_std_logic;
------------------------------------------------------------------------
    function to_shift_array
    (
        hyperram_header : std_logic_vector(47 downto 0)
    )
    return hyperram_shift_array
    is
        variable retval : hyperram_shift_array := (others => (others => '0'));
    begin
        retval := (0 => hyperram_header(47 downto 32),
                   1 => hyperram_header(31 downto 16),
                   2 => hyperram_header(15 downto 0));

        return retval;
        
    end to_shift_array;
------------------------------------------------------------------------
    function read_data_from_hyperram_memory
    (
        start_address : integer
    )
    return std_logic_vector
    is
        variable return_value : std_logic_vector(47 downto 0);
    begin
        return_value(transaction_type_1_read_0_write'range)          := "1";
        return_value(select_memory_with_1_and_register_with_0'range) := "0";
        return_value(linear_burst_with_0_wrapped_with_1'range)       := "0";
        return_value(row_and_upper_column_address'range)             := to_std_logic(0,13);
        return_value(reserved'range)                                 := to_std_logic(0,13);
        return_value(lower_column_address'range)                     := to_std_logic(0,3);

        return return_value;

    end read_data_from_hyperram_memory;

------------------------------------------------------------------------
    function write_data_to_hyperram
    (
        start_address       : integer;
        number_of_registers : integer
    )
    return std_logic_vector
    is
        variable return_value : std_logic_vector(47 downto 0);
    begin
        return_value(transaction_type_1_read_0_write'range)          := "0";
        return_value(select_memory_with_1_and_register_with_0'range) := "0";
        return_value(linear_burst_with_0_wrapped_with_1'range)       := "0";
        return_value(row_and_upper_column_address'range)             := to_std_logic(0,row_and_upper_column_address'length);
        return_value(reserved'range)                                 := to_std_logic(0,reserved'length);
        return_value(lower_column_address'range)                     := to_std_logic(0,lower_column_address'length);

        return return_value;

    end write_data_to_hyperram;
------------------------------------------------------------------------

end package body hyperram_interface_pkg;
