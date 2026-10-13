library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

-- HyperRAM command/address frame definitions and controller interface records.
-- Based on testbench/hyperram/hyperram_interface_pkg.vhd.
-- Bit assignments follow Winbond W959D8NFYA (HyperRAM 2.0, 512Mb dual die).
package hyperram_pkg is

    -- command/address (CA) frame, CA[47:0], sent msb byte first
    subtype hyperram_header is std_logic_vector(47 downto 0);

    subtype transaction_type_1_read_0_write          is std_logic_vector(47 downto 47);
    subtype select_register_with_1_and_memory_with_0 is std_logic_vector(46 downto 46);
    subtype linear_burst_with_1_wrapped_with_0       is std_logic_vector(45 downto 45);
    subtype row_and_upper_column_address             is std_logic_vector(44 downto 16);
    subtype reserved                                 is std_logic_vector(15 downto 3);
    subtype lower_column_address                     is std_logic_vector(2 downto 0);

    -- word addresses, die 1 is selected with address bit 24
    subtype hyperram_address is unsigned(24 downto 0);
    constant die1_offset : natural := 2**24;

    constant id_register_0     : natural := 16#0000#;
    constant id_register_1     : natural := 16#0001#;
    constant config_register_0 : natural := 16#0800#;
    constant config_register_1 : natural := 16#0801#;

    -- expected register contents of W959D8NFYA
    constant id_register_0_die0 : std_logic_vector(15 downto 0) := x"0F86";
    constant id_register_0_die1 : std_logic_vector(15 downto 0) := x"4F86";
    constant id_register_1_value : std_logic_vector(15 downto 0) := x"0001";
    constant config_register_0_default : std_logic_vector(15 downto 0) := x"8F2F";

    function build_hyperram_header (
        read_transaction : boolean;
        register_space   : boolean;
        address          : natural)
        return hyperram_header;

    function get_header_byte (
        header : hyperram_header;
        index  : natural)
        return std_logic_vector;

    -- CR0[7:4] encoding of initial latency count
    function latency_to_config_bits ( latency_count : natural)
        return std_logic_vector;

------------------------------------------------------------------------
    type hyperram_command is (none, read, write);

    type hyperram_in_record is record
        command          : hyperram_command;
        register_space   : boolean;
        address          : natural range 0 to 2**25-1;
        burst_length     : natural range 1 to 512;  -- 16 bit words
        write_data       : std_logic_vector(15 downto 0);
        write_data_valid : boolean;
        latency_count    : natural range 3 to 7;     -- must match CR0[7:4]
    end record;

    constant init_hyperram_in : hyperram_in_record := (
        command          => none,
        register_space   => false,
        address          => 0,
        burst_length     => 1,
        write_data       => (others => '0'),
        write_data_valid => false,
        latency_count    => 7);

    type hyperram_out_record is record
        is_ready             : boolean;
        write_data_requested : boolean;
        read_data            : std_logic_vector(15 downto 0);
        read_data_is_ready   : boolean;
        transaction_is_done  : boolean;
        read_timed_out       : boolean;
    end record;

    type hyperram_fpga_out_record is record
        ck       : std_logic;
        cs_n     : std_logic;
        reset_n  : std_logic;
        dq_out   : std_logic_vector(7 downto 0);
        dq_oe    : std_logic;
        rwds_out : std_logic;
        rwds_oe  : std_logic;
    end record;

    type hyperram_fpga_in_record is record
        dq_in   : std_logic_vector(7 downto 0);
        rwds_in : std_logic;
    end record;

    -- pins of a DDR controller (hyperram_axi), through DDIO registers. hi is the first half of the
    -- clock period (rising edge), lo the second half.
    --   ck_hi/ck_lo to the CK pin, its DDIO clocked by the inverted 90 degree clock
    --   cs_n, dq_*, rwds_* clocked by the 0 degree hyperram clock, reset_n by the system clock
    type hyperram_ddr_fpga_out_record is record
        ck_hi    : std_logic;
        ck_lo    : std_logic;
        cs_n     : std_logic;
        reset_n  : std_logic;
        dq_hi    : std_logic_vector(7 downto 0);
        dq_lo    : std_logic_vector(7 downto 0);
        dq_oe    : std_logic;
        rwds_hi  : std_logic;
        rwds_lo  : std_logic;
        rwds_oe  : std_logic;
    end record;

    -- input DDIO registers clocked by the phase shifted read clock
    type hyperram_ddr_fpga_in_record is record
        dq_hi   : std_logic_vector(7 downto 0);
        dq_lo   : std_logic_vector(7 downto 0);
        rwds_hi : std_logic;
        rwds_lo : std_logic;
    end record;

    -- dynamic phase shift of the read clock, to the PLL
    type pll_phase_shift_record is record
        shift        : std_logic_vector(2 downto 0);
        shift_select : std_logic_vector(4 downto 0);
        shift_enable : std_logic;
    end record;

------------------------------------------------------------------------
    procedure init_hyperram (
        signal self : out hyperram_in_record);

    procedure request_hyperram_read (
        signal self    : out hyperram_in_record;
        address        : natural;
        burst_length   : natural := 1;
        register_space : boolean := false);

    procedure request_hyperram_write (
        signal self    : out hyperram_in_record;
        address        : natural;
        burst_length   : natural := 1;
        register_space : boolean := false);

    procedure send_hyperram_write_data (
        signal self : out hyperram_in_record;
        data        : std_logic_vector(15 downto 0));

    function hyperram_is_ready ( self : hyperram_out_record)
        return boolean;

    function hyperram_write_data_is_requested ( self : hyperram_out_record)
        return boolean;

    function hyperram_read_data_is_ready ( self : hyperram_out_record)
        return boolean;

    function get_hyperram_read_data ( self : hyperram_out_record)
        return std_logic_vector;

    function hyperram_transaction_is_done ( self : hyperram_out_record)
        return boolean;

end package hyperram_pkg;

package body hyperram_pkg is

------------------------------------------------------------------------
    function build_hyperram_header
    (
        read_transaction : boolean;
        register_space   : boolean;
        address          : natural
    )
    return hyperram_header
    is
        variable retval      : hyperram_header := (others => '0');
        variable std_address : std_logic_vector(31 downto 0);
    begin
        std_address := std_logic_vector(to_unsigned(address, 32));

        if read_transaction then
            retval(transaction_type_1_read_0_write'range) := "1";
        end if;
        if register_space then
            retval(select_register_with_1_and_memory_with_0'range) := "1";
        end if;
        retval(linear_burst_with_1_wrapped_with_0'range)       := "1";
        retval(row_and_upper_column_address'range)            := std_address(31 downto 3);
        retval(reserved'range)                                 := (others => '0');
        retval(lower_column_address'range)                    := std_address(2 downto 0);

        return retval;
    end build_hyperram_header;
------------------------------------------------------------------------
    function get_header_byte
    (
        header : hyperram_header;
        index  : natural
    )
    return std_logic_vector
    is
    begin
        return header(47 - 8*index downto 40 - 8*index);
    end get_header_byte;
------------------------------------------------------------------------
    function latency_to_config_bits
    (
        latency_count : natural
    )
    return std_logic_vector
    is
    begin
        CASE latency_count is
            WHEN 3      => return "1110";
            WHEN 4      => return "1111";
            WHEN 5      => return "0000";
            WHEN 6      => return "0001";
            WHEN others => return "0010";
        end CASE;
    end latency_to_config_bits;
------------------------------------------------------------------------
    procedure init_hyperram
    (
        signal self : out hyperram_in_record
    ) is
    begin
        self.command          <= none;
        self.write_data_valid <= false;
    end init_hyperram;
------------------------------------------------------------------------
    procedure request_hyperram_read
    (
        signal self    : out hyperram_in_record;
        address        : natural;
        burst_length   : natural := 1;
        register_space : boolean := false
    ) is
    begin
        self.command        <= read;
        self.address        <= address;
        self.burst_length   <= burst_length;
        self.register_space <= register_space;
    end request_hyperram_read;
------------------------------------------------------------------------
    procedure request_hyperram_write
    (
        signal self    : out hyperram_in_record;
        address        : natural;
        burst_length   : natural := 1;
        register_space : boolean := false
    ) is
    begin
        self.command        <= write;
        self.address        <= address;
        self.burst_length   <= burst_length;
        self.register_space <= register_space;
    end request_hyperram_write;
------------------------------------------------------------------------
    procedure send_hyperram_write_data
    (
        signal self : out hyperram_in_record;
        data        : std_logic_vector(15 downto 0)
    ) is
    begin
        self.write_data       <= data;
        self.write_data_valid <= true;
    end send_hyperram_write_data;
------------------------------------------------------------------------
    function hyperram_is_ready ( self : hyperram_out_record) return boolean is
    begin
        return self.is_ready;
    end hyperram_is_ready;

    function hyperram_write_data_is_requested ( self : hyperram_out_record) return boolean is
    begin
        return self.write_data_requested;
    end hyperram_write_data_is_requested;

    function hyperram_read_data_is_ready ( self : hyperram_out_record) return boolean is
    begin
        return self.read_data_is_ready;
    end hyperram_read_data_is_ready;

    function get_hyperram_read_data ( self : hyperram_out_record) return std_logic_vector is
    begin
        return self.read_data;
    end get_hyperram_read_data;

    function hyperram_transaction_is_done ( self : hyperram_out_record) return boolean is
    begin
        return self.transaction_is_done;
    end hyperram_transaction_is_done;
------------------------------------------------------------------------
end package body hyperram_pkg;
