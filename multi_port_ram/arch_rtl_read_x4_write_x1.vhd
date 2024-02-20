architecture rtl of ram_read_x4_write_x1 is

begin

    u_mpram1 : entity work.ram_read_x2_write_x1
    generic map(initial_values)
    port map(
    clock          ,
    ram_read_a_in  ,
    ram_read_a_out ,
    ram_read_b_in  ,
    ram_read_b_out ,
    ram_write_in);

    u_mpram2 : entity work.ram_read_x2_write_x1
    generic map(initial_values)
    port map(
    clock          ,
    ram_read_c_in  ,
    ram_read_c_out ,
    ram_read_d_in  ,
    ram_read_d_out ,
    ram_write_in);

end rtl;
