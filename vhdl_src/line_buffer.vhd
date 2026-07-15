library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sobel_pkg.all;

entity line_buffer is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        pixel_in    : in  std_logic_vector(7 downto 0);  -- incoming pixel
        pixel_valid : in  std_logic;  -- TVALID equivalent
        tlast_in    : in  std_logic;                      
        tuser_in    : in  std_logic;                      

        window_out  : out pixel_window_t;   -- the 9 pixels
        window_valid: out std_logic   --the window is ready this cycle
    );
end entity line_buffer;

architecture rtl of line_buffer is

    constant IMG_WIDTH : integer := 640;  -- my image width

    -- The two BRAM delay lines (row N-1 and row N-2)
    type bram_t is array (0 to IMG_WIDTH-1) of std_logic_vector(7 downto 0);
    signal row_buf1 : bram_t := (others => (others => '0')); -- stores row N-1
    signal row_buf2 : bram_t := (others => (others => '0')); -- stores row N-2

    -- The shared write/read address counter
    signal col_addr : integer range 0 to IMG_WIDTH-1 := 0;

    -- Outputs of each BRAM delay line (before the horizontal shift regs)
    signal row1_pixel : std_logic_vector(7 downto 0);  -- current pixel of row N-1
    signal row2_pixel : std_logic_vector(7 downto 0);  -- current pixel of row N-2

    -- Small horizontal shift register type: 2 elements (1-ago, 2-ago)
    type shift_reg_t is array (0 to 1) of std_logic_vector(7 downto 0);

    -- One shift register per row (row 0 = live/current row, row 1 = N-1, row 2 = N-2)
    signal row0_sr : shift_reg_t := (others => (others => '0'));
    signal row1_sr : shift_reg_t := (others => (others => '0'));
    signal row2_sr : shift_reg_t := (others => (others => '0'));

    -- Valid-window tracking (it counts filled pixels/rows before window_valid caan go high)
    signal fill_count : integer range 0 to (IMG_WIDTH * 2 + 3) := 0;

begin
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            col_addr   <= 0;
            fill_count <= 0;
            window_valid <= '0';
        elsif pixel_valid = '1' then

            -- Step 1: READ before WRITE (capture the "old" value at this address
            -- BEFORE we overwrite it with the new incoming pixel)
            row1_pixel <= row_buf1(col_addr);   -- this is row N-1's current pixel
            row2_pixel <= row_buf2(col_addr);   -- this is row N-2's current pixel

            -- Step 2: WRITE the new values into the BRAMs at this same address
            row_buf1(col_addr) <= pixel_in;      -- store live pixel for future row N-1
            row_buf2(col_addr) <= row1_pixel;    -- store row N-1's pixel for future row N-2

            -- Step 3: shift the horizontal (column-delay) registers for all 3 rows
            row0_sr(1) <= row0_sr(0);
            row0_sr(0) <= pixel_in;

            row1_sr(1) <= row1_sr(0);
            row1_sr(0) <= row1_pixel;

            row2_sr(1) <= row2_sr(0);
            row2_sr(0) <= row2_pixel;

            -- Step 4: advance the counter, wrapping at IMG_WIDTH
            if tuser_in = '1' then
                col_addr <= 0;          -- Start of Frame
            elsif tlast_in = '1' then
                col_addr <= 0;          -- End of Frame
            elsif col_addr = IMG_WIDTH - 1 then
                col_addr <= 0;          -- End of Row (The missing piece!)
            else
                col_addr <= col_addr + 1;
            end if;

	    -- Step 5: Drive the 9 pixels to the window_out port
            window_out(0) <= row2_sr(1);  -- Top-Left
            window_out(1) <= row2_sr(0);  -- Top-Center
            window_out(2) <= row2_pixel;  -- Top-Right
            window_out(3) <= row1_sr(1);  -- Mid-Left
            window_out(4) <= row1_sr(0);  -- Center
            window_out(5) <= row1_pixel;  -- Mid-Right
            window_out(6) <= row0_sr(1);  -- Bot-Left
            window_out(7) <= row0_sr(0);  -- Bot-Center
            window_out(8) <= pixel_in;    -- Bot-Right

	    -- Step 6: Warm-up counter for window_valid
            if fill_count < (IMG_WIDTH * 2 + 3) then
                fill_count <= fill_count + 1;
                window_valid <= '0';  -- Not ready yet
            else
                window_valid <= '1';  -- BRAMs are full, window is valid
            end if;

        end if;
    end if;
end process;
end architecture rtl;