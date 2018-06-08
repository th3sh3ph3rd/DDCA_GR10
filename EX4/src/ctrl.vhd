library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.core_pack.all;
use work.op_pack.all;

entity ctrl is
	
	port (
            clk : in std_logic;
            reset : in std_logic;
            cop_op : in cop0_op_type; --from decode
            wrdata : in std_logic_vector(DATA_WIDTH-1 downto 0); --from decode exec_op.rddata
	    pc_in_dec : in std_logic_vector(PC_WIDTH-1 downto 0); --from decode pc_out
	    pc_in_exec : in std_logic_vector(PC_WIDTH-1 downto 0); --from exec pc_out
	    pc_in_mem : in std_logic_vector(PC_WIDTH-1 downto 0); --from mem pc_out, new pc after branch
            bds : in std_logic; --from decode, exec_op.branch or exec_op.link
	    pcsrc_in : in std_logic; --from mem
            exc_ovf : in std_logic; --from exec
            intr : in std_logic_vector(INTR_COUNT-1 downto 0);
            rddata : out std_logic_vector(DATA_WIDTH-1 downto 0); --to exec cop_rddata
            pcsrc_out : out std_logic; --to fetch
            pc_out : out std_logic_vector(PC_WIDTH-1 downto 0); --to fetch
            flush_decode : out std_logic;
            flush_exec : out std_logic
        );

end ctrl;

architecture rtl of ctrl is

    type COPROCESSOR_REGISTERS is record	
        status : std_logic_vector(DATA_WIDTH-1 downto 0);
      	cause : std_logic_vector(DATA_WIDTH-1 downto 0);
        epc : std_logic_vector(DATA_WIDTH-1 downto 0);
        npc : std_logic_vector(DATA_WIDTH-1 downto 0);
    end record;

    signal cop_reg, cop_reg_next : COPROCESSOR_REGISTERS;

    alias exc_next : std_logic_vector(3 downto 0) is cop_reg_next.cause(5 downto 2);
    alias pen_next : std_logic_vector(2 downto 0) is cop_reg_next.cause(12 downto 10);
    alias B_next : std_logic is cop_reg_next.cause(31);
    alias I : std_logic is cop_reg.status(0);
    alias I_next : std_logic is cop_reg_next.status(0);

    signal cop_op_reg : cop0_op_type;
    signal bds_reg0, bds_reg1 : std_logic;
    signal surpress_branch, surpress_branch_next : std_logic;

begin  -- rtl

    sync : process(all)
    begin

        if reset = '0' then
            cop_reg <= ((0 => '1', others => '0'), (others => '0'), (others => '0'), (others => '0'));
	    cop_op_reg <= COP0_NOP;
	    bds_reg0 <= '0';
	    bds_reg1 <= '0';
	    surpress_branch <= '0';
        elsif rising_edge(clk) then
            cop_reg <= cop_reg_next;
            cop_op_reg <= cop_op;
	    bds_reg0 <= bds;
            bds_reg1 <= bds_reg0;
	    surpress_branch <= surpress_branch_next;
        end if;

    end process;

    output : process(all)
    begin
	if surpress_branch = '1' then
	    pcsrc_out <= '0';
	else
            pcsrc_out <= pcsrc_in;
	end if;

        pc_out <= pc_in_mem; --new pc after branch

        rddata <= (others => '0');

        --branch hazard resolution
        flush_decode <= pcsrc_in;
        flush_exec <= pcsrc_in;
        
        cop_reg_next <= cop_reg;	
	surpress_branch_next <= '0';
		
        --ALU ovf detected
        if exc_ovf = '1' then
            exc_next <= "1100";
            B_next <= bds_reg1; --branch delay slot
            pcsrc_out <= '1';
            pc_out <= EXCEPTION_PC;
            flush_decode <= '1';
            flush_exec <= '1';
        end if;

        --interrupt detected, interrupt pipeline in decode stage, pc in exec points to instr in decode
        if intr /= "000" and I = '1' then
            exc_next <= "0000";
            pen_next <= intr;
	    if bds_reg0 = '1' then --interrupted instr in bds, restart branch instr (instr before bds)
            	B_next <= '1';
		cop_reg_next.epc(PC_WIDTH-1 downto 0) <= std_logic_vector(unsigned(pc_in_exec)-4);
		cop_reg_next.npc(PC_WIDTH-1 downto 0) <= std_logic_vector(unsigned(pc_in_exec)-4);
		surpress_branch_next <= '1'; --surpress possible branch in next cycle
	    else --restart interrupted instr
		cop_reg_next.epc(PC_WIDTH-1 downto 0) <= pc_in_exec;
		cop_reg_next.npc(PC_WIDTH-1 downto 0) <= pc_in_exec;
	    end if;
            I_next <= '0'; --disable interrupts
            pcsrc_out <= '1';
            pc_out <= EXCEPTION_PC;
            flush_decode <= '1';
        end if;

        --register io multiplex
        case cop_op_reg.addr is
            when "01100" =>
                if cop_op_reg.wr = '1' then
                    cop_reg_next.status <= wrdata;
                end if;
                rddata <= cop_reg.status;
            when "01101" =>
                if cop_op_reg.wr = '1' then
                    cop_reg_next.cause <= wrdata;
                end if;
                rddata <= cop_reg.cause;
            when "01110" =>
                if cop_op_reg.wr = '1' then
                    cop_reg_next.epc <= wrdata;
                end if;
                rddata <= cop_reg.epc;
            when "01111" =>
                if cop_op_reg.wr = '1' then
                    cop_reg_next.npc <= wrdata;
                end if;
                rddata <= cop_reg.npc;
            when others =>
        end case;

    end process;    

end rtl;
