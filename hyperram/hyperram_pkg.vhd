library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package hyperram_pkg is
------------------------------------------------------------------------
    type hyperram_record is record
        hyperram_is_done : boolean;
        hyperram_is_requested : boolean;
    end record;

    constant init_hyperram : hyperram_record := (false, false);
------------------------------------------------------------------------
    procedure create_hyperram (
        signal self : inout hyperram_record);
------------------------------------------------------------------------
    procedure request_hyperram (
        signal self : out hyperram_record);
------------------------------------------------------------------------
    function hyperram_is_ready (self : hyperram_record)
        return boolean;
------------------------------------------------------------------------
end package hyperram_pkg;

package body hyperram_pkg is
------------------------------------------------------------------------
    procedure create_hyperram 
    (
        signal self : inout hyperram_record
    ) 
    is
    begin
        self.hyperram_is_requested <= false;
        if self.hyperram_is_requested then
            self.hyperram_is_done <= true;
        else
            self.hyperram_is_done <= false;
        end if;
    end procedure;

------------------------------------------------------------------------
    procedure request_hyperram
    (
        signal self : out hyperram_record
    ) is
    begin
        self.hyperram_is_requested <= true;
        
    end request_hyperram;

------------------------------------------------------------------------
    function hyperram_is_ready
    (
        self : hyperram_record
    )
    return boolean
    is
    begin
        return self.hyperram_is_done;
    end hyperram_is_ready;

------------------------------------------------------------------------
end package body hyperram_pkg;
