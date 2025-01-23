
LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 

package sample_trigger_generic_pkg is
    generic (g_ram_depth : positive);

    type sample_trigger_record is record
        trigger_enabled       : boolean ;
        triggered             : boolean;
        ram_write_enabled     : boolean;
        write_counter         : natural range 0 to g_ram_depth-1;
        sample_requested      : boolean;
        write_after_triggered : natural range 0 to g_ram_depth-1;
    end record;

    constant init_trigger : sample_trigger_record := (false,false, false, 0, false, g_ram_depth-1);

    procedure create_trigger(signal self : inout sample_trigger_record; trigger_detected : in boolean);
    procedure prime_trigger(signal self : inout sample_trigger_record; samples_after_trigger : natural);

end package sample_trigger_generic_pkg;

package body sample_trigger_generic_pkg is

---------------------------------------------
    procedure create_trigger(signal self : inout sample_trigger_record; trigger_detected : in boolean) is
    begin
        if self.write_after_triggered > 0 then
            if self.write_counter < g_ram_depth-1  then
                self.write_counter <= self.write_counter + 1;
            else
                self.write_counter <= 0;
            end if;
        end if;

        self.triggered <= (self.triggered or trigger_detected) and self.trigger_enabled;

        if self.triggered then
            if self.write_after_triggered > 0 then
                self.write_after_triggered <= self.write_after_triggered - 1;
            else
                self.trigger_enabled <= false;
            end if;
        end if;
    end create_trigger;

---------------------------------------------
    procedure prime_trigger(signal self : inout sample_trigger_record; samples_after_trigger : natural) is
    begin
        if not self.trigger_enabled then
            self.trigger_enabled <= true;
            self.write_after_triggered <= samples_after_trigger;
        end if;
    end prime_trigger;
---------------------------------------------

end package body sample_trigger_generic_pkg;


