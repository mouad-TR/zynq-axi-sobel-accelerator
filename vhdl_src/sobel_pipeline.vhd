library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sobel_pkg.all;

entity sobel_pipeline is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        pixel_in    : in  std_logic_vector(7 downto 0);
        pixel_valid_in : in std_logic;
	tlast_in    : in std_logic;                      
        tuser_in    : in std_logic;                      

        pixel_out   : out std_logic_vector(7 downto 0);
        pixel_valid_out : out std_logic
    );
end entity sobel_pipeline;

architecture struct of sobel_pipeline is

    signal window_sig       : pixel_window_t;
    signal window_valid_sig : std_logic;

begin

    lb: entity work.line_buffer
        port map (
            clk          => clk,
            rst          => rst,
            pixel_in     => pixel_in,
            pixel_valid  => pixel_valid_in,
	    tlast_in     => tlast_in,                    
            tuser_in     => tuser_in,                    
            window_out   => window_sig,
            window_valid => window_valid_sig
        );

    sb: entity work.sobel
        port map (
            clk          => clk,
            rst          => rst,
            window_in    => window_sig,
            window_valid => window_valid_sig,
            pixel_out    => pixel_out,
            pixel_valid  => pixel_valid_out
        );

end architecture struct;