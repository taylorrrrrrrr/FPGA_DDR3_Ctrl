`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: lauchinyuan
// Email: lauchinyuan@yeah.net
// Create Date: 2023/12/17 10:45:22
// Module Name: multichan_ddr_interface
// Description: 多通道DDR读写接口, 包括多通道读接口, 多通道写接口, MIG IP核
// 用户读写数据接口 <---> 多通道读/写接口 <---> MIG IP核(AXI从机) <---> DDR3 PHY接口
//////////////////////////////////////////////////////////////////////////////////


module multichan_ddr_interface
#(parameter FIFO_WR_WIDTH           = 'd32           ,  //用户端FIFO读写位宽
            FIFO_RD_WIDTH           = 'd32           ,
            AXI_WIDTH               = 'd64           ,  //AXI总线读写数据位宽
            AXI_AXSIZE              = 3'b011         ,  //AXI总线的axi_awsize, 需要与AXI_WIDTH对应

            //写FIFO相关参数
            WR_FIFO_RAM_DEPTH       = 'd2048         , //写FIFO内部RAM存储器深度
            WR_FIFO_RAM_ADDR_WIDTH  = 'd11           , //写FIFO内部RAM读写地址宽度, log2(WR_FIFO_RAM_DEPTH)
            WR_FIFO_WR_IND          = 'd1            , //写FIFO单次写操作访问的ram_mem单元个数 FIFO_WR_WIDTH/WR_FIFO_RAM_WIDTH
            WR_FIFO_RD_IND          = 'd2            , //写FIFO单次读操作访问的ram_mem单元个数 AXI_WIDTH/WR_FIFO_RAM_ADDR_WIDTH        
            WR_FIFO_RAM_WIDTH       = FIFO_WR_WIDTH  , //写FIFO RAM存储器的位宽
            WR_FIFO_WR_L2           = 'd0            , //log2(WR_FIFO_WR_IND)
            WR_FIFO_RD_L2           = 'd1            , //log2(WR_FIFO_RD_IND)
            WR_FIFO_RAM_RD2WR       = 'd2            , //读数据位宽和写数据位宽的比, 即一次读取的RAM单元深度, RAM_RD2WR = RD_WIDTH/WR_WIDTH, 当读位宽小于等于写位宽时, 值为1   

            //读FIFO相关参数
            RD_FIFO_RAM_DEPTH       = 'd2048         , //读FIFO内部RAM存储器深度
            RD_FIFO_RAM_ADDR_WIDTH  = 'd11           , //读FIFO内部RAM读写地址宽度, log2(RD_FIFO_RAM_DEPTH)
            RD_FIFO_WR_IND          = 'd2            , //读FIFO单次写操作访问的ram_mem单元个数 AXI_WIDTH/RD_FIFO_RAM_WIDTH
            RD_FIFO_RD_IND          = 'd1            , //读FIFO单次读操作访问的ram_mem单元个数 FIFO_RD_WIDTH/RD_FIFO_RAM_ADDR_WIDTH        
            RD_FIFO_RAM_WIDTH       = FIFO_RD_WIDTH  , //读FIFO RAM存储器的位宽
            RD_FIFO_WR_L2           = 'd1            , //log2(RD_FIFO_WR_IND)
            RD_FIFO_RD_L2           = 'd0            , //log2(RD_FIFO_RD_IND)
            RD_FIFO_RAM_RD2WR       = 'd1              //读数据位宽和写数据位宽的比, 即一次读取的RAM单元深度, RAM_RD2WR = RD_WIDTH/WR_WIDTH, 当读位宽小于等于写位宽时, 值为1 
)
(
        input   wire                        clk             , //DDR系统时钟
        input   wire                        rst_n           ,   
                        
        //用户端写接口              
        input   wire                        wr_clk          , //写FIFO写时钟
        input   wire                        wr_rst          , //写复位, 高电平有效
        input   wire [29:0]                 wr_beg_addr0    , //写通道0写起始地址
        input   wire [29:0]                 wr_beg_addr1    , //写通道1写起始地址
        input   wire [29:0]                 wr_beg_addr2    , //写通道2写起始地址
        input   wire [29:0]                 wr_beg_addr3    , //写通道3写起始地址
        input   wire [29:0]                 wr_end_addr0    , //写通道0写终止地址
        input   wire [29:0]                 wr_end_addr1    , //写通道1写终止地址
        input   wire [29:0]                 wr_end_addr2    , //写通道2写终止地址
        input   wire [29:0]                 wr_end_addr3    , //写通道3写终止地址
        input   wire [7:0]                  wr_burst_len0   , //写通道0写突发长度
        input   wire [7:0]                  wr_burst_len1   , //写通道1写突发长度
        input   wire [7:0]                  wr_burst_len2   , //写通道2写突发长度
        input   wire [7:0]                  wr_burst_len3   , //写通道3写突发长度
        input   wire                        wr_en0          , //写通道0写请求
        input   wire                        wr_en1          , //写通道1写请求
        input   wire                        wr_en2          , //写通道2写请求
        input   wire                        wr_en3          , //写通道3写请求
        input   wire [FIFO_WR_WIDTH-1:0]    wr_data0        , //写通道0写入数据
        input   wire [FIFO_WR_WIDTH-1:0]    wr_data1        , //写通道1写入数据
        input   wire [FIFO_WR_WIDTH-1:0]    wr_data2        , //写通道2写入数据
        input   wire [FIFO_WR_WIDTH-1:0]    wr_data3        , //写通道3写入数据

        //用户端写接口
        input   wire                        rd_clk          , //读FIFO读时钟
        input   wire                        rd_rst          , //读复位, 高电平有效
        input   wire                        rd_mem_enable   , //读存储器使能, 防止存储器未写先读
        input   wire [29:0]                 rd_beg_addr0    , //读通道0读起始地址
        input   wire [29:0]                 rd_beg_addr1    , //读通道1读起始地址
        input   wire [29:0]                 rd_beg_addr2    , //读通道2读起始地址
        input   wire [29:0]                 rd_beg_addr3    , //读通道3读起始地址
        input   wire [29:0]                 rd_end_addr0    , //读通道0读终止地址
        input   wire [29:0]                 rd_end_addr1    , //读通道1读终止地址
        input   wire [29:0]                 rd_end_addr2    , //读通道2读终止地址
        input   wire [29:0]                 rd_end_addr3    , //读通道3读终止地址
        input   wire [7:0]                  rd_burst_len0   , //读通道0读突发长度
        input   wire [7:0]                  rd_burst_len1   , //读通道1读突发长度
        input   wire [7:0]                  rd_burst_len2   , //读通道2读突发长度
        input   wire [7:0]                  rd_burst_len3   , //读通道3读突发长度
        input   wire                        rd_en0          , //读通道0读请求
        input   wire                        rd_en1          , //读通道1读请求
        input   wire                        rd_en2          , //读通道2读请求
        input   wire                        rd_en3          , //读通道3读请求
        output  wire [FIFO_RD_WIDTH-1:0]    rd_data0        , //读通道0读出数据
        output  wire [FIFO_RD_WIDTH-1:0]    rd_data1        , //读通道1读出数据
        output  wire [FIFO_RD_WIDTH-1:0]    rd_data2        , //读通道2读出数据
        output  wire [FIFO_RD_WIDTH-1:0]    rd_data3        , //读通道3读出数据
        output  wire                        rd_valid0       , //读通道0FIFO可读标志          
        output  wire                        rd_valid1       , //读通道1FIFO可读标志          
        output  wire                        rd_valid2       , //读通道2FIFO可读标志          
        output  wire                        rd_valid3       , //读通道3FIFO可读标志

        //MIG IP核用户端
        output  wire                        ui_clk          , //MIG IP核输出的用户时钟, 用作AXI控制器时钟
        output  wire                        ui_rst          , //MIG IP核输出的复位信号, 高电平有效
        output  wire                        calib_done      , //DDR3初始化完成
        
        //DDR3 PHY接口
        output  wire [14:0]                 ddr3_addr       ,  
        output  wire [2:0]                  ddr3_ba         ,
        output  wire                        ddr3_cas_n      ,
        output  wire                        ddr3_ck_n       ,
        output  wire                        ddr3_ck_p       ,
        output  wire                        ddr3_cke        ,
        output  wire                        ddr3_ras_n      ,
        output  wire                        ddr3_reset_n    ,
        output  wire                        ddr3_we_n       ,
        inout   wire [31:0]                 ddr3_dq         ,
        inout   wire [3:0]                  ddr3_dqs_n      ,
        inout   wire [3:0]                  ddr3_dqs_p      ,
        output  wire                        ddr3_cs_n       ,
        output  wire [3:0]                  ddr3_dm         ,
        output  wire                        ddr3_odt                    

    );
    
    //本地参数
    localparam AXI_WSTRB_W = AXI_WIDTH >> 3;
    
    //AXI总线
    //AXI4写地址通道
    wire [3:0]              w_axi_awid    ; 
    wire [29:0]             w_axi_awaddr  ;
    wire [7:0]              w_axi_awlen   ; //突发传输长度
    wire [2:0]              w_axi_awsize  ; //突发传输大小(Byte)
    wire [1:0]              w_axi_awburst ; //突发类型
    wire                    w_axi_awlock  ; 
    wire [3:0]              w_axi_awcache ; 
    wire [2:0]              w_axi_awprot  ;
    wire [3:0]              w_axi_awqos   ;
    wire                    w_axi_awvalid ; //写地址valid
    wire                    w_axi_awready ; //从机发出的写地址ready
    
    //写数据通道
    wire [AXI_WIDTH-1:0]    w_axi_wdata   ; //写数据
    wire [AXI_WSTRB_W-1:0]  w_axi_wstrb   ; //写数据有效字节线
    wire                    w_axi_wlast   ; //最后一个数据标志
    wire                    w_axi_wvalid  ; //写数据有效标志
    wire                    w_axi_wready  ; //从机发出的写数据ready
                
    //写响应通道         
    wire [3:0]              w_axi_bid     ;
    wire [1:0]              w_axi_bresp   ; //响应信号,表征写传输是否成功
    wire                    w_axi_bvalid  ; //响应信号valid标志
    wire                    w_axi_bready  ; //主机响应ready信号
    
    //读地址通道
    wire [3:0]              w_axi_arid    ; 
    wire [29:0]             w_axi_araddr  ; 
    wire [7:0]              w_axi_arlen   ; //突发传输长度
    wire [2:0]              w_axi_arsize  ; //突发传输大小(Byte)
    wire [1:0]              w_axi_arburst ; //突发类型
    wire                    w_axi_arlock  ; 
    wire [3:0]              w_axi_arcache ; 
    wire [2:0]              w_axi_arprot  ;
    wire [3:0]              w_axi_arqos   ;
    wire                    w_axi_arvalid ; //读地址valid
    wire                    w_axi_arready ; //从机准备接收读地址
    
    //读数据通道
    wire [AXI_WIDTH-1:0]    w_axi_rdata   ; //读数据
    wire [1:0]              w_axi_rresp   ; //收到的读响应
    wire                    w_axi_rlast   ; //最后一个数据标志
    wire                    w_axi_rvalid  ; //读数据有效标志
    wire                    w_axi_rready  ; //主机发出的读数据ready
    
    //输入系统时钟异步复位、同步释放处理
    reg                     rst_n_d1      ;
    reg                     rst_n_sync    ;
    
    //rst_n_d1、rst_n_sync
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n) begin  //异步复位
            rst_n_d1    <= 1'b0;
            rst_n_sync  <= 1'b0;
        end else begin   //同步释放
            rst_n_d1    <= 1'b1;
            rst_n_sync  <= rst_n_d1;
        end
    end    
    
    
    //多通道写接口
    wr_multichan_interface
    #(.FIFO_WR_WIDTH           (FIFO_WR_WIDTH           ), //写FIFO在用户端操作的位宽
      .AXI_WIDTH               (AXI_WIDTH               ), //AXI总线数据位宽
      //写FIFO相关参数         
      .WR_FIFO_RAM_DEPTH       (WR_FIFO_RAM_DEPTH       ), //写FIFO内部RAM存储器深度
      .WR_FIFO_RAM_ADDR_WIDTH  (WR_FIFO_RAM_ADDR_WIDTH  ), //写FIFO内部RAM读写地址宽度, log2(WR_FIFO_RAM_DEPTH)
      .WR_FIFO_WR_IND          (WR_FIFO_WR_IND          ), //写FIFO单次写操作访问的ram_mem单元个数 FIFO_WR_WIDTH/WR_FIFO_RAM_WIDTH
      .WR_FIFO_RD_IND          (WR_FIFO_RD_IND          ), //写FIFO单次写操作访问的ram_mem单元个数 AXI_WIDTH/WR_FIFO_RAM_ADDR_WIDTH        
      .WR_FIFO_RAM_WIDTH       (WR_FIFO_RAM_WIDTH       ), //写FIFO RAM存储器的位宽
      .WR_FIFO_WR_L2           (WR_FIFO_WR_L2           ), //log2(WR_FIFO_WR_IND)
      .WR_FIFO_RD_L2           (WR_FIFO_RD_L2           ), //log2(WR_FIFO_RD_IND)
      .WR_FIFO_RAM_RD2WR       (WR_FIFO_RAM_RD2WR       ), //读数据位宽和写数据位宽的比, 即一次读取的RAM单元深度, RAM_RD2WR = RD_WIDTH/WR_WIDTH, 当读位宽小于等于写位宽时, 值为1 
    
      .AXI_WSTRB_W             (AXI_WSTRB_W             )
    )
    wr_multichan_interface_inst
    (

        .clk             (ui_clk          ), //AXI主机读写时钟
        .rst_n           (~ui_rst         ),  
        //用户端               
        .wr_clk          (wr_clk          ), //写FIFO写时钟
        .wr_rst          (wr_rst          ), //写复位, 高电平有效
        .wr_beg_addr0    (wr_beg_addr0    ), //写通道0写起始地址
        .wr_beg_addr1    (wr_beg_addr1    ), //写通道1写起始地址
        .wr_beg_addr2    (wr_beg_addr2    ), //写通道2写起始地址
        .wr_beg_addr3    (wr_beg_addr3    ), //写通道3写起始地址
        .wr_end_addr0    (wr_end_addr0    ), //写通道0写终止地址
        .wr_end_addr1    (wr_end_addr1    ), //写通道1写终止地址
        .wr_end_addr2    (wr_end_addr2    ), //写通道2写终止地址
        .wr_end_addr3    (wr_end_addr3    ), //写通道3写终止地址
        .wr_burst_len0   (wr_burst_len0   ), //写通道0写突发长度
        .wr_burst_len1   (wr_burst_len1   ), //写通道1写突发长度
        .wr_burst_len2   (wr_burst_len2   ), //写通道2写突发长度
        .wr_burst_len3   (wr_burst_len3   ), //写通道3写突发长度
        .wr_en0          (wr_en0          ), //写通道0写请求
        .wr_en1          (wr_en1          ), //写通道1写请求
        .wr_en2          (wr_en2          ), //写通道2写请求
        .wr_en3          (wr_en3          ), //写通道3写请求
        .wr_data0        (wr_data0        ), //写通道0写入数据
        .wr_data1        (wr_data1        ), //写通道1写入数据
        .wr_data2        (wr_data2        ), //写通道2写入数据
        .wr_data3        (wr_data3        ), //写通道3写入数据
        
        //AXI写相关通道线
        //AXI4写地址通道
        .m_axi_awid      (w_axi_awid      ), 
        .m_axi_awaddr    (w_axi_awaddr    ),
        .m_axi_awlen     (w_axi_awlen     ), //突发传输长度
        .m_axi_awsize    (w_axi_awsize    ), //突发传输大小(Byte)
        .m_axi_awburst   (w_axi_awburst   ), //突发类型
        .m_axi_awlock    (w_axi_awlock    ), 
        .m_axi_awcache   (w_axi_awcache   ), 
        .m_axi_awprot    (w_axi_awprot    ),
        .m_axi_awqos     (w_axi_awqos     ),
        .m_axi_awvalid   (w_axi_awvalid   ), //写地址valid
        .m_axi_awready   (w_axi_awready   ), //从机发出的写地址ready
            
        //写数据通道 
        .m_axi_wdata     (w_axi_wdata     ), //写数据
        .m_axi_wstrb     (w_axi_wstrb     ), //写数据有效字节线
        .m_axi_wlast     (w_axi_wlast     ), //最后一个数据标志
        .m_axi_wvalid    (w_axi_wvalid    ), //写数据有效标志
        .m_axi_wready    (w_axi_wready    ), //从机发出的写数据ready
            
        //写响应通道 
        .m_axi_bid       (w_axi_bid       ),
        .m_axi_bresp     (w_axi_bresp     ), //响应信号,表征写传输是否成功
        .m_axi_bvalid    (w_axi_bvalid    ), //响应信号valid标志
        .m_axi_bready    (w_axi_bready    )  //主机响应ready信号        
    );    
    

    
    //多通道读接口
    rd_multichan_interface
    #(.FIFO_RD_WIDTH           (FIFO_RD_WIDTH           ), //读FIFO在用户端操作的位宽
      .AXI_WIDTH               (AXI_WIDTH               ), //AXI总线数据位宽
                                                 
      //读FIFO相关参数                            
      .RD_FIFO_RAM_DEPTH       (RD_FIFO_RAM_DEPTH       ), //读FIFO内部RAM存储器深度
      .RD_FIFO_RAM_ADDR_WIDTH  (RD_FIFO_RAM_ADDR_WIDTH  ), //读FIFO内部RAM读写地址宽度, log2(RD_FIFO_RAM_DEPTH)
      .RD_FIFO_WR_IND          (RD_FIFO_WR_IND          ), //读FIFO单次写操作访问的ram_mem单元个数 AXI_WIDTH/RD_FIFO_RAM_WIDTH
      .RD_FIFO_RD_IND          (RD_FIFO_RD_IND          ), //读FIFO单次读操作访问的ram_mem单元个数 FIFO_RD_WIDTH/RD_FIFO_RAM_ADDR_WIDTH        
      .RD_FIFO_RAM_WIDTH       (RD_FIFO_RAM_WIDTH       ), //读FIFO RAM存储器的位宽
      .RD_FIFO_WR_L2           (RD_FIFO_WR_L2           ), //log2(RD_FIFO_WR_IND)
      .RD_FIFO_RD_L2           (RD_FIFO_RD_L2           ), //log2(RD_FIFO_RD_IND)
      .RD_FIFO_RAM_RD2WR       (RD_FIFO_RAM_RD2WR       )  //读数据位宽和写数据位宽的比, 即一次读取的RAM单元深度, RAM_RD2WR = RD_WIDTH/WR_WIDTH, 当读位宽小于等于写位宽时, 值为1  
    )
    rd_multichan_interface_inst
    (
        .clk             (ui_clk          ), //AXI主机读写时钟
        .rst_n           (~ui_rst         ),   
                        
        //用户端               
        .rd_clk          (rd_clk          ), //读FIFO读时钟
        .rd_rst          (rd_rst          ), //读复位, 高电平有效
        .rd_mem_enable   (rd_mem_enable   ), //读存储器使能, 防止存储器未写先读
        .rd_beg_addr0    (rd_beg_addr0    ), //读通道0读起始地址
        .rd_beg_addr1    (rd_beg_addr1    ), //读通道1读起始地址
        .rd_beg_addr2    (rd_beg_addr2    ), //读通道2读起始地址
        .rd_beg_addr3    (rd_beg_addr3    ), //读通道3读起始地址
        .rd_end_addr0    (rd_end_addr0    ), //读通道0读终止地址
        .rd_end_addr1    (rd_end_addr1    ), //读通道1读终止地址
        .rd_end_addr2    (rd_end_addr2    ), //读通道2读终止地址
        .rd_end_addr3    (rd_end_addr3    ), //读通道3读终止地址
        .rd_burst_len0   (rd_burst_len0   ), //读通道0读突发长度
        .rd_burst_len1   (rd_burst_len1   ), //读通道1读突发长度
        .rd_burst_len2   (rd_burst_len2   ), //读通道2读突发长度
        .rd_burst_len3   (rd_burst_len3   ), //读通道3读突发长度
        .rd_en0          (rd_en0          ), //读通道0读请求
        .rd_en1          (rd_en1          ), //读通道1读请求
        .rd_en2          (rd_en2          ), //读通道2读请求
        .rd_en3          (rd_en3          ), //读通道3读请求
        .rd_data0        (rd_data0        ), //读通道0读出数据
        .rd_data1        (rd_data1        ), //读通道1读出数据
        .rd_data2        (rd_data2        ), //读通道2读出数据
        .rd_data3        (rd_data3        ), //读通道3读出数据
        .rd_valid0       (rd_valid0       ), //读通道0FIFO可读标志          
        .rd_valid1       (rd_valid1       ), //读通道1FIFO可读标志          
        .rd_valid2       (rd_valid2       ), //读通道2FIFO可读标志          
        .rd_valid3       (rd_valid3       ), //读通道3FIFO可读标志      

        //MIG IP核 AXI接口(连接至AXI从机)
        //AXI4读地址通道
        .m_axi_arid      (w_axi_arid      ), 
        .m_axi_araddr    (w_axi_araddr    ),
        .m_axi_arlen     (w_axi_arlen     ), //突发传输长度
        .m_axi_arsize    (w_axi_arsize    ), //突发传输大小(Byte)
        .m_axi_arburst   (w_axi_arburst   ), //突发类型
        .m_axi_arlock    (w_axi_arlock    ), 
        .m_axi_arcache   (w_axi_arcache   ), 
        .m_axi_arprot    (w_axi_arprot    ),
        .m_axi_arqos     (w_axi_arqos     ),
        .m_axi_arvalid   (w_axi_arvalid   ), //读地址valid
        .m_axi_arready   (w_axi_arready   ), //从机准备接收读地址
            
        //读数据通道 
        .m_axi_rdata     (w_axi_rdata     ), //读数据
        .m_axi_rresp     (w_axi_rresp     ), //收到的读响应
        .m_axi_rlast     (w_axi_rlast     ), //最后一个数据标志
        .m_axi_rvalid    (w_axi_rvalid    ), //读数据有效标志
        .m_axi_rready    (w_axi_rready    )  //主机发出的读数据ready
    );
    
    //MIG IP核
    //Vivado MIG IP核
    axi_ddr3 axi_ddr3_mig_inst (
        // DDR3存储器接口
        .ddr3_addr              (ddr3_addr          ),  // output [14:0]    ddr3_addr
        .ddr3_ba                (ddr3_ba            ),  // output [2:0]     ddr3_ba
        .ddr3_cas_n             (ddr3_cas_n         ),  // output           ddr3_cas_n
        .ddr3_ck_n              (ddr3_ck_n          ),  // output [0:0]     ddr3_ck_n
        .ddr3_ck_p              (ddr3_ck_p          ),  // output [0:0]     ddr3_ck_p
        .ddr3_cke               (ddr3_cke           ),  // output [0:0]     ddr3_cke
        .ddr3_ras_n             (ddr3_ras_n         ),  // output           ddr3_ras_n
        .ddr3_reset_n           (ddr3_reset_n       ),  // output           ddr3_reset_n
        .ddr3_we_n              (ddr3_we_n          ),  // output           ddr3_we_n
        .ddr3_dq                (ddr3_dq            ),  // inout [31:0]     ddr3_dq
        .ddr3_dqs_n             (ddr3_dqs_n         ),  // inout [3:0]      ddr3_dqs_n
        .ddr3_dqs_p             (ddr3_dqs_p         ),  // inout [3:0]      ddr3_dqs_p
        .init_calib_complete    (calib_done         ),  // output           init_calib_complete
        .ddr3_cs_n              (ddr3_cs_n          ),  // output [0:0]     ddr3_cs_n
        .ddr3_dm                (ddr3_dm            ),  // output [3:0]     ddr3_dm
        .ddr3_odt               (ddr3_odt           ),  // output [0:0]     ddr3_odt
        
        // 用户接口
        .ui_clk                 (ui_clk             ),  // output           ui_clk
        .ui_clk_sync_rst        (ui_rst             ),  // output           ui_clk_sync_rst
        .mmcm_locked            (                   ),  // output           mmcm_locked
        .aresetn                (rst_n_sync         ),  // input            aresetn
        .app_sr_req             (1'b0               ),  // input            app_sr_req
        .app_ref_req            (1'b0               ),  // input            app_ref_req
        .app_zq_req             (1'b0               ),  // input            app_zq_req
        .app_sr_active          (                   ),  // output           app_sr_active
        .app_ref_ack            (                   ),  // output           app_ref_ack
        .app_zq_ack             (                   ),  // output           app_zq_ack
        
        // AXI写地址通道
        .s_axi_awid             (w_axi_awid         ),  // input [3:0]      s_axi_awid
        .s_axi_awaddr           (w_axi_awaddr       ),  // input [29:0]     s_axi_awaddr
        .s_axi_awlen            (w_axi_awlen        ),  // input [7:0]      s_axi_awlen
        .s_axi_awsize           (w_axi_awsize       ),  // input [2:0]      s_axi_awsize
        .s_axi_awburst          (w_axi_awburst      ),  // input [1:0]      s_axi_awburst
        .s_axi_awlock           (w_axi_awlock       ),  // input [0:0]      s_axi_awlock
        .s_axi_awcache          (w_axi_awcache      ),  // input [3:0]      s_axi_awcache
        .s_axi_awprot           (w_axi_awprot       ),  // input [2:0]      s_axi_awprot
        .s_axi_awqos            (w_axi_awqos        ),  // input [3:0]      s_axi_awqos
        .s_axi_awvalid          (w_axi_awvalid      ),  // input            s_axi_awvalid
        .s_axi_awready          (w_axi_awready      ),  // output           s_axi_awready
        
        // AXI写数据通道
        .s_axi_wdata            (w_axi_wdata        ),  // input [AXI_WIDTH-1:0]     s_axi_wdata
        .s_axi_wstrb            (w_axi_wstrb        ),  // input [AXI_WSTRB_W-1:0]   s_axi_wstrb
        .s_axi_wlast            (w_axi_wlast        ),  // input                     s_axi_wlast
        .s_axi_wvalid           (w_axi_wvalid       ),  // input                     s_axi_wvalid
        .s_axi_wready           (w_axi_wready       ),  // output                    s_axi_wready
                    
        // AXI写响应通道        
        .s_axi_bid              (w_axi_bid          ),  // output [3:0]              s_axi_bid
        .s_axi_bresp            (w_axi_bresp        ),  // output [1:0]              s_axi_bresp
        .s_axi_bvalid           (w_axi_bvalid       ),  // output                    s_axi_bvalid
        .s_axi_bready           (w_axi_bready       ),  // input                     s_axi_bready
                    
        // AXI读地址通道        
        .s_axi_arid             (w_axi_arid           ),  // input [3:0]               s_axi_arid
        .s_axi_araddr           (w_axi_araddr         ),  // input [29:0]              s_axi_araddr
        .s_axi_arlen            (w_axi_arlen          ),  // input [7:0]               s_axi_arlen
        .s_axi_arsize           (w_axi_arsize         ),  // input [2:0]               s_axi_arsize
        .s_axi_arburst          (w_axi_arburst        ),  // input [1:0]               s_axi_arburst
        .s_axi_arlock           (w_axi_arlock         ),  // input [0:0]               s_axi_arlock
        .s_axi_arcache          (w_axi_arcache        ),  // input [3:0]               s_axi_arcache
        .s_axi_arprot           (w_axi_arprot         ),  // input [2:0]               s_axi_arprot
        .s_axi_arqos            (w_axi_arqos          ),  // input [3:0]               s_axi_arqos
        .s_axi_arvalid          (w_axi_arvalid        ),  // input                     s_axi_arvalid
        .s_axi_arready          (w_axi_arready        ),  // output                    s_axi_arready
        
        // AXI读数据通道
        .s_axi_rid              (                     ),  // output [3:0]              s_axi_rid
        .s_axi_rdata            (w_axi_rdata          ),  // output [AXI_WIDTH-1:0]    s_axi_rdata
        .s_axi_rresp            (w_axi_rresp          ),  // output [1:0]              s_axi_rresp
        .s_axi_rlast            (w_axi_rlast          ),  // output                    s_axi_rlast
        .s_axi_rvalid           (w_axi_rvalid         ),  // output                    s_axi_rvalid
        .s_axi_rready           (w_axi_rready         ),  // input                     s_axi_rready
        
        // 系统时钟
        .sys_clk_i              (clk                ),
        // 参考时钟
        .clk_ref_i              (clk                ),
        .sys_rst                (rst_n_sync         )   // input            sys_rst
    );    
    
endmodule
