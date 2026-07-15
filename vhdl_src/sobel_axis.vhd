library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sobel_pkg.all;

entity sobel_axis is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;

        -- AXI4-Stream slave (input side, from camera/DMA)
        s_axis_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in  std_logic;   -- end of row marker
        s_axis_tuser  : in  std_logic;   -- start of frame marker

        -- AXI4-Stream master (output side, to DMA back to memory)
        m_axis_tdata  : out std_logic_vector(7 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic;
        m_axis_tuser  : out std_logic
    );
end entity sobel_axis;

architecture rtl of sobel_axis is

    signal tlast_d1, tlast_d2 : std_logic := '0';
    signal tuser_d1, tuser_d2 : std_logic := '0';

begin

    s_axis_tready <= '1';

    core: entity work.sobel_pipeline
        port map (
            clk             => clk,
            rst             => rst,
            pixel_in        => s_axis_tdata,
            pixel_valid_in  => s_axis_tvalid,
	    tlast_in        => s_axis_tlast,             
            tuser_in        => s_axis_tuser,             
            pixel_out       => m_axis_tdata,
            pixel_valid_out => m_axis_tvalid
        );

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tlast_d1 <= '0'; tlast_d2 <= '0';
                tuser_d1 <= '0'; tuser_d2 <= '0';
            else
                tlast_d1 <= s_axis_tlast;
                tlast_d2 <= tlast_d1;

                tuser_d1 <= s_axis_tuser;
                tuser_d2 <= tuser_d1;
            end if;
        end if;
    end process;

    m_axis_tlast <= tlast_d2;
    m_axis_tuser <= tuser_d2;

end architecture rtl;