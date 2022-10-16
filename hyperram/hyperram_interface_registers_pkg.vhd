library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package hyperram_interface_registers_pkg is

    type hyperram_data_array is array (integer range 0 to 2) of std_logic_vector(15 downto 0);

    type hyperram_header_record is record
        transaction_type_1_read_0_write          : std_logic_vector(47 downto 47);
        select_memory_with_1_and_register_with_0 : std_logic_vector(46 downto 46);
        linear_burst_with_0_wrapped_with_1       : std_logic_vector(45 downto 45);
        row_and_upper_column_address             : std_logic_vector(44 downto 16);
        reserved                                 : std_logic_vector(15 downto 3);
        lower_column_address                     : std_logic_vector(2 downto 0);
    end record;

    function to_std_logic ( number : integer; size : integer)
        return std_logic_vector ;

    constant read_register_linear : hyperram_header_record := (
        transaction_type_1_read_0_write          => "1",
        select_memory_with_1_and_register_with_0 => "0",
        linear_burst_with_0_wrapped_with_1       => "0",
        row_and_upper_column_address             => to_std_logic(0,13),
        reserved                                 => to_std_logic(0,13),
        lower_column_address                     => to_std_logic(0,3));

    constant write_register_linear : hyperram_header_record := (
        transaction_type_1_read_0_write          => "1",
        select_memory_with_1_and_register_with_0 => "0",
        linear_burst_with_0_wrapped_with_1       => "0",
        row_and_upper_column_address             => to_std_logic(0,13),
        reserved                                 => to_std_logic(0,13),
        lower_column_address                     => to_std_logic(0,3));


end package hyperram_interface_registers_pkg;

package body hyperram_interface_registers_pkg is

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

    function write_data_to_hyperram_memory
    (
        start_address : integer
    )
    return hyperram_data_array
    is
        variable return_value : hyperram_data_array;
    begin
        -- return_value(0) := (

        return return_value;

    end write_data_to_hyperram_memory;

end package body hyperram_interface_registers_pkg;
