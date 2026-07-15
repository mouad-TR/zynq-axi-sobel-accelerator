library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sobel_pkg.all;

entity sobel is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        window_in    : in  pixel_window_t;   -- the 9 pixels from line_buffer
        window_valid : in  std_logic;

        pixel_out    : out std_logic_vector(7 downto 0);
        pixel_valid  : out std_logic
    );
end entity sobel;


architecture rtl of sobel is

    signal gx, gy   : signed(10 downto 0);  -- 11-bit signed, as we sized
    signal abs_gx, abs_gy : unsigned(9 downto 0);  -- 10-bit unsigned (0-1023)
    signal magnitude : unsigned(10 downto 0);       -- 11-bit unsigned (0-2047)

begin
    process(clk)
        variable a,b,c,d,f,g,h,i : signed(8 downto 0); -- 9-bit signed (pixel + sign headroom)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pixel_valid <= '0';
            elsif window_valid = '1' then

                -- Convert unsigned 8-bit pixels to signed 9-bit for safe subtraction
                a := signed('0' & window_in(0));
                b := signed('0' & window_in(1));
                c := signed('0' & window_in(2));
                d := signed('0' & window_in(3));
                f := signed('0' & window_in(5));
                g := signed('0' & window_in(6));
                h := signed('0' & window_in(7));
                i := signed('0' & window_in(8));

                -- Gx = (C - A) + 2*(F - D) + (I - G)
                gx <= resize(c - a, 11) + resize(shift_left(resize(f - d, 11), 1), 11) + resize(i - g, 11);

                -- Gy = (G - A) + 2*(H - B) + (I - C)
                gy <= resize(g - a, 11) + resize(shift_left(resize(h - b, 11), 1), 11) + resize(i - c, 11);

                pixel_valid <= '1';
            else
                pixel_valid <= '0';
            end if;
        end if;
    end process;

    magnitude <= resize(unsigned(abs(gx)), 11) + resize(unsigned(abs(gy)), 11);

    pixel_out <= std_logic_vector(to_unsigned(255, 8)) when magnitude > 255
            else std_logic_vector(resize(magnitude, 8));

end architecture rtl;