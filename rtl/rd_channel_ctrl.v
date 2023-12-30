`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: lauchinyuan
// Email: lauchinyuan@yeah.net
// Create Date: 2023/12/04 14:33:11
// Module Name: rd_channel_ctrl
// Description: 单一读通道控制器, 内部集成读FIFO
// 当FIFO内数据量不够时, 向多通道仲裁器mulchan_rd_arbiter发出读SDRAM请求
//////////////////////////////////////////////////////////////////////////////////

module rd_channel_ctrl
    #(parameter FIFO_RD_WIDTH           = 'd32              , //读FIFO在用户端操作的位宽
                AXI_WIDTH               = 'd64              , //AXI总线数据位宽
                    
                //读FIFO相关参数 
                RD_FIFO_RAM_DEPTH       = 'd2048            , //读FIFO内部RAM存储器深度
                RD_FIFO_RAM_ADDR_WIDTH  = 'd11              , //读FIFO内部RAM读写地址宽度, log2(RD_FIFO_RAM_DEPTH)
                RD_FIFO_WR_IND          = 'd2               , //读FIFO单次写操作访问的ram_mem单元个数 AXI_WIDTH/RD_FIFO_RAM_WIDTH
                RD_FIFO_RD_IND          = 'd1               , //读FIFO单次读操作访问的ram_mem单元个数 FIFO_RD_WIDTH/RD_FIFO_RAM_ADDR_WIDTH        
                RD_FIFO_RAM_WIDTH       = FIFO_RD_WIDTH     , //读FIFO RAM存储器的位宽
                RD_FIFO_WR_L2           = 'd1               , //log2(RD_FIFO_WR_IND)
                RD_FIFO_RD_L2           = 'd0               , //log2(RD_FIFO_RD_IND)
                RD_FIFO_RAM_RD2WR       = 'd1                 //读数据位宽和写数据位宽的比, 即一次读取的RAM单元深度, RAM_RD2WR = RD_WIDTH/WR_WIDTH, 当读位宽小于等于写位宽时, 值为1   
    )
    (
        input   wire                        clk             , //AXI主机读写时钟
        input   wire                        rst_n           ,   
                        
        //用户端               
        input   wire                        rd_clk          , //读FIFO读时钟
        input   wire                        rd_rst          , //读复位, 高电平有效
        input   wire                        rd_mem_enable   , //读存储器使能, 防止存储器未写先读
        input   wire [29:0]                 rd_beg_addr     , //读起始地址
        input   wire [29:0]                 rd_end_addr     , //读终止地址
        input   wire [7:0]                  rd_burst_len    , //读突发长度
        input   wire                        rd_en           , //读FIFO读请求
        output  wire [FIFO_RD_WIDTH-1:0]    rd_data         , //读FIFO读数据
        output  wire                        rd_valid        , //读FIFO可读标志,表示读FIFO中有数据可以对外输出    

        //AXI读主机端           
        input   wire                        axi_reading     , //AXI主机读正在进行
        input   wire [AXI_WIDTH-1:0]        axi_rd_data     , //从AXI读主机读到的数据,写入读FIFO
        input   wire                        axi_rd_done     , //AXI主机完成一次写操作
        
        //读通道仲裁器端
        input   wire                        rd_grant        , //仲裁器发来的授权
        output  reg                         rd_req          , //发送到仲裁器的读请求
        output  reg [29:0]                  rd_addr         , //发送到仲裁器的读地址
        output  wire[7:0]                   rd_len            //发送到仲裁器的读突发长度
       
    );
    
    
    //自定义FIFO参数计算
    parameter   RD_FIFO_WR_CNT_WIDTH = RD_FIFO_RAM_ADDR_WIDTH + 'd1 - RD_FIFO_WR_L2 , //读FIFO写端口计数器的位宽
                RD_FIFO_RD_CNT_WIDTH = RD_FIFO_RAM_ADDR_WIDTH + 'd1 - RD_FIFO_RD_L2 ; //读FIFO读端口计数器的位宽

    //FIFO数据数量计数器   
    wire [10:0]  cnt_rd_fifo_wrport      ;  //读FIFO写端口(对接AXI读主机)数据数量

    //真实的读突发长度
    wire  [7:0] real_rd_len              ;  //真实的读突发长度,是rd_burst_len+1    

    //突发地址增量, 每次进行一次连续突发传输地址的增量, 在外边计算, 方便后续复用
    wire  [29:0]burst_rd_addr_inc        ;
    
    //复位信号处理(异步复位同步释放)
    reg     rst_n_sync  ;  //同步释放处理后的rst_n
    reg     rst_n_d1    ;  //同步释放处理rst_n, 同步器第一级输出 

    //读复位同步到clk
    reg     rd_rst_sync ;  //读复位打两拍
    reg     rd_rst_d1   ;  //读复位打一拍
    

    //rst_n相对clk同步释放
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n) begin  //异步复位
            rst_n_d1    <= 1'b0;
            rst_n_sync  <= 1'b0;
        end else begin
            rst_n_d1    <= 1'b1;
            rst_n_sync  <= rst_n_d1;
        end
    end
    
    //读复位同步释放到clk, 作为读fifo的复位输入
    always@(posedge clk or posedge rd_rst) begin
        if(rd_rst) begin
            rd_rst_d1   <= 1'b1;
            rd_rst_sync <= 1'b1;
        end else begin
            rd_rst_d1   <= 1'b0;
            rd_rst_sync <= rd_rst_d1;
        end
    end
       
    //真实的读突发长度
    assign real_rd_len = rd_burst_len + 8'd1;
    
    //突发地址增量, 右移3的
    assign burst_rd_addr_inc = real_rd_len * AXI_WIDTH >> 3;
    
    //向AXI主机发出的读突发长度
    assign rd_len = rd_burst_len;  
    
    //rd_req
    //读请求信号
    always@(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            rd_req <= 1'b0;
        end else if(cnt_rd_fifo_wrport < 512 && rd_mem_enable) begin //非授权状态下, fifo数量不够时拉高
            rd_req <= 1'b1;
        end else if(rd_grant) begin  //被授权后拉低读请求
            rd_req <= 1'b0;
        end else begin
            rd_req <= rd_req;
        end
    end 
    
    //rd_addr
    //读地址, 注意只有grant信号有效时才进行正常的地址自增
    always@(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            rd_addr <= rd_beg_addr;
        end else if(rd_rst) begin
            rd_addr <= rd_beg_addr;
        end else if(rd_grant && axi_rd_done && rd_addr > (rd_end_addr - {burst_rd_addr_inc[28:0], 1'b0} + 30'd1)) begin
        //每次写完成后判断是否超限, 下一个写首地址后续的空间已经不够再进行一次突发写操作, 位拼接的作用是×2
            rd_addr <= rd_beg_addr;
        end else if(rd_grant && axi_rd_done) begin
            rd_addr <= rd_addr + burst_rd_addr_inc;
        end else begin
            rd_addr <= rd_addr;
        end
    end
    

    //读FIFO, 从SDRAM中读出的数据先暂存于此
    //使用自行编写的异步FIFO模块
    async_fifo
    #(.RAM_DEPTH       (RD_FIFO_RAM_DEPTH       ), //内部RAM存储器深度
      .RAM_ADDR_WIDTH  (RD_FIFO_RAM_ADDR_WIDTH  ), //内部RAM读写地址宽度, 需与RAM_DEPTH匹配
      .WR_WIDTH        (AXI_WIDTH               ), //写数据位宽
      .RD_WIDTH        (FIFO_RD_WIDTH           ), //读数据位宽
      .WR_IND          (RD_FIFO_WR_IND          ), //单次写操作访问的ram_mem单元个数
      .RD_IND          (RD_FIFO_RD_IND          ), //单次读操作访问的ram_mem单元个数         
      .RAM_WIDTH       (RD_FIFO_RAM_WIDTH       ), //读端口数据位宽更小,使用读数据位宽作为RAM存储器的位宽
      .WR_CNT_WIDTH    (RD_FIFO_WR_CNT_WIDTH    ), //FIFO写端口计数器的位宽
      .RD_CNT_WIDTH    (RD_FIFO_RD_CNT_WIDTH    ), //FIFO读端口计数器的位宽
      .WR_L2           (RD_FIFO_WR_L2           ), //log2(WR_IND), 决定写地址有效数据位个数及RAM位宽
      .RD_L2           (RD_FIFO_RD_L2           ), //log2(RD_IND), 决定读地址有效低位
      .RAM_RD2WR       (RD_FIFO_RAM_RD2WR       )  //读数据位宽和写数据位宽的比, 即一次读取的RAM单元深度, RAM_RD2WR = RD_WIDTH/WR_WIDTH, 当读位宽小于等于写位宽时, 值为1     
                )
    rd_fifo_inst
    (
            //写相关
            .wr_clk          (clk                        ),  //写端口时钟是AXI主机时钟, 从axi_master_rd模块写入数据
            .wr_rst_n        (rst_n_sync  & ~rd_rst_sync ),  //读复位时需要复位读FIFO
            .wr_en           (axi_reading & rd_grant     ),  //axi_master_rd正在读时,FIFO也在写入
            .wr_data         (axi_rd_data                ),  //从axi_master_rd模块写入数据
            .fifo_full       (                           ),  //FIFO写满
            .wr_data_count   (cnt_rd_fifo_wrport         ),  //读FIFO写端口(对接AXI读主机)数据数量
            //读相关
            .rd_clk          (rd_clk                     ),  //读端口时钟
            .rd_rst_n        (rst_n_sync & ~rd_rst_sync  ),  //读复位时需要复位读FIFO 
            .rd_en           (rd_en                      ),  //读FIFO读使能
            .rd_data         (rd_data                    ),  //读FIFO读取的数据
            .fifo_empty      (rd_fifo_empty              ),  //FIFO读空
            .rd_data_count   (                           )   //读端口数据个数,按读端口数据位宽计算
    );
    //自定义FIFO没有复位busy信号
    assign rd_fifo_wr_rst_busy = 1'b0;
    
    //读FIFO可读标志,表示读FIFO中有数据可以对外输出
    assign rd_valid = ~rd_fifo_empty;    
    
    
endmodule