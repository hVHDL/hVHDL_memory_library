------------------------------------------------------------------------
-- Simple dual port ram: one port only writes, the other only reads, one clock.
--
-- The block RAMs' simple dual port mode is twice as wide as their true dual
-- port mode (Efinix Titanium: 512 x 20 against 1024 x 10 a 10 kbit block), so
-- a ram that is written on one port and read on the other takes about half the
-- blocks it does as dual_port_ram, which synthesis maps true dual port.
--
-- The records, init values and procedures are dual_port_ram_pkg's, as for
-- dual_port_ram: write_data_to_ram(write_in, ...) on the write port,
-- request_data_from_ram(read_in, ...), ram_read_is_ready(read_out) and
-- get_ram_data(read_out) on the read port. write_in's read request and
-- read_in's write request and data are not used.
--
-- read latency: 2 clocks with the output register (g_output_register, the
-- default), 1 without, as dual_port_ram. A read of the address written in the
-- same clock returns the old contents (read first).
------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.dual_port_ram_pkg.all;

entity simple_dual_port_ram is
    generic(
       g_dpram_subtype : dpram_ref_record
       ; g_ram_init_values : work.dual_port_ram_pkg.ram_array
       ; g_output_register : boolean := true);

    port (
        clock    : in std_logic;
        write_in : in work.dual_port_ram_pkg.ram_in_record;
        read_in  : in work.dual_port_ram_pkg.ram_in_record;
        read_out : out work.dual_port_ram_pkg.ram_out_record
    );
end entity simple_dual_port_ram;

architecture rtl of simple_dual_port_ram is

    -- a read takes 2 clocks with the output register, 1 without
    constant read_latency : natural := 1 + boolean'pos(g_output_register);

    signal ram_contents    : g_ram_init_values'subtype := g_ram_init_values;
    signal read_pipeline   : std_logic_vector(read_latency-1 downto 0) := (others => '0');
    signal output_buffer   : std_logic_vector(read_out.data'range) := (others => '0');
    signal output_register : std_logic_vector(read_out.data'range) := (others => '0');

begin
    read_out.data          <= output_register when g_output_register else output_buffer;
    read_out.data_is_ready <= read_pipeline(read_pipeline'left);

    -- the vendors' simple dual port template: a write port and a registered read port in
    -- one process, the read seeing the contents before this clock's write
    create_ram : process(clock)
    begin
        if rising_edge(clock) then
            read_pipeline   <= read_pipeline(read_pipeline'left-1 downto 0) & read_in.read_is_requested;
            output_register <= output_buffer;
            if write_in.write_requested = '1' then
                ram_contents(to_integer(write_in.address)) <= write_in.data;
            end if;
            if read_in.read_is_requested = '1' then
                output_buffer <= ram_contents(to_integer(read_in.address));
            end if;
        end if;
    end process;

end rtl;
