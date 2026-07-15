library ieee;
use ieee.std_logic_1164.all;

package sobel_pkg is
    type pixel_window_t is array (0 to 8) of std_logic_vector(7 downto 0);
end package sobel_pkg;