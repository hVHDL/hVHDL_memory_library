
LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 

package sample_trigger_generic_pkg is
    generic (g_ram_depth : positive);

    type sample_trigger_record is record
        trigger_enabled       : boolean ;
        triggered             : boolean;
        ram_write_enabled     : boolean;
        write_address_counter : natural range 0 to g_ram_depth-1;
        sample_requested      : boolean;
        write_after_triggered : natural range 0 to g_ram_depth-1;

        stop_sampling : boolean;
    end record;

    constant init_trigger : sample_trigger_record := (false,false, false, 0, false, g_ram_depth-1, true);

    procedure create_trigger(signal self : inout sample_trigger_record; trigger_detected : in boolean);
    procedure prime_trigger(signal self : inout sample_trigger_record; samples_after_trigger : natural);
    function last_trigger_detected(self : sample_trigger_record) return boolean;
    procedure enable_sampling(signal self : inout sample_trigger_record);
    function sampling_enabled(self : sample_trigger_record) return boolean;
    function get_sample_address(self : sample_trigger_record) return natural;

end package sample_trigger_generic_pkg;

package body sample_trigger_generic_pkg is

---------------------------------------------
    procedure create_trigger(
        signal self : inout sample_trigger_record
        ; trigger_detected : in boolean
        ; event : in boolean) is
    begin
        self.triggered <= (self.triggered or trigger_detected) and self.trigger_enabled;

        if event then
            if self.write_after_triggered > 0 then
                if self.write_address_counter < g_ram_depth-1  then
                    self.write_address_counter <= self.write_address_counter + 1;
                else
                    self.write_address_counter <= 0;
                end if;
            end if;


            if self.triggered then
                if self.write_after_triggered > 0 then
                    self.write_after_triggered <= self.write_after_triggered - 1;
                end if;
            end if;

            if last_trigger_detected(self) then
                self.trigger_enabled <= false;
                self.stop_sampling <= true;
            end if;
        end if;

    end create_trigger;

    procedure create_trigger(
        signal self : inout sample_trigger_record
        ; trigger_detected : in boolean) is
    begin
        create_trigger(self, trigger_detected, event => true);
    end create_trigger;
---------------------------------------------
    function last_trigger_detected(self : sample_trigger_record) return boolean is
    begin
        return self.triggered and self.write_after_triggered = 0;
    end function;
---------------------------------------------
    procedure prime_trigger(signal self : inout sample_trigger_record; samples_after_trigger : natural) is
    begin
        if not self.trigger_enabled then
            self.trigger_enabled <= true;
            self.write_after_triggered <= samples_after_trigger;
        end if;
    end prime_trigger;
---------------------------------------------
    procedure enable_sampling(signal self : inout sample_trigger_record)
    is
    begin
        self.stop_sampling <= false;
    end enable_sampling;
---------------------------------------------
    function sampling_enabled(self : sample_trigger_record) return boolean is
    begin
        return (not self.stop_sampling);
    end sampling_enabled;
---------------------------------------------
    function get_sample_address(self : sample_trigger_record) return natural is
    begin
        return self.write_address_counter;
    end get_sample_address;
---------------------------------------------
end package body sample_trigger_generic_pkg;
