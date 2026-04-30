/*
 * VGA Air Hockey peripheral
 *
 * Register map (32-bit Avalon MM slave, word addressing):
 *   Addr  Byte   Dir  Description
 *   0     0x00   R    STATUS: bit[0] = VSYNC_READY (1 during vblank)
 *   4     0x10   W    PUCK_POS: bits[15:0]=X, bits[31:16]=Y
 *
 * Fmax (Slow 1100mV 85C): TBD after synthesis
 */

module vga_ball(
   input  logic        clk,
   input  logic        reset,
   // Avalon MM slave
   input  logic        chipselect,
   input  logic        write,
   input  logic [2:0]  address,
   input  logic [31:0] writedata,
   output logic [31:0] readdata,
   // VGA
   output logic [7:0]  VGA_R, VGA_G, VGA_B,
   output logic        VGA_CLK, VGA_HS, VGA_VS,
                       VGA_BLANK_n,
   output logic        VGA_SYNC_n
);

   logic [10:0] hcount;
   logic [9:0]  vcount;

   vga_counters counters(.clk50(clk), .*);

   logic [9:0] px, py;
   assign px = hcount[10:1];
   assign py = vcount;

   // Puck position registers (reset to centre)
   logic [9:0] puck_x, puck_y;

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         puck_x <= 10'd320;
         puck_y <= 10'd240;
      end else if (chipselect && write && address == 3'd4) begin
         puck_x <= writedata[9:0];    // X from bits [15:0]
         puck_y <= writedata[25:16];  // Y from bits [31:16]
      end
   end

   // Avalon read
   always_comb begin
      readdata = 32'd0;
      if (address == 3'd0)
         readdata = {31'd0, (vcount >= 10'd480)};  // VSYNC_READY
   end

   // Centre-circle distance squared
   logic signed [11:0] cdx, cdy;
   logic [23:0] cdist2;
   assign cdx    = $signed({2'b00, px}) - 12'sd320;
   assign cdy    = $signed({2'b00, py}) - 12'sd240;
   assign cdist2 = cdx * cdx + cdy * cdy;

   // Puck distance squared
   logic signed [11:0] pdx, pdy;
   logic [23:0] pdist2;
   assign pdx    = $signed({2'b00, px}) - $signed({2'b00, puck_x});
   assign pdy    = $signed({2'b00, py}) - $signed({2'b00, puck_y});
   assign pdist2 = pdx * pdx + pdy * pdy;

   // Rink geometry
   localparam WL = 10,  WR = 629, WT = 10,  WB = 469;
   localparam WW = 4;
   localparam GT = 190, GB = 290;
   localparam C_LO    = 24'd2116, C_HI    = 24'd2916;  // 46²..54² centre ring
   localparam PUCK_R2 = 24'd100;                        // puck radius 10 px

   always_comb begin
      {VGA_R, VGA_G, VGA_B} = 24'h000000;

      if (VGA_BLANK_n) begin
         // 1. Navy blue (border + walls)
         {VGA_R, VGA_G, VGA_B} = 24'h1a1a2e;

         // 2. Ice surface inside walls
         if (px >= WL + WW && px <= WR - WW &&
             py >= WT + WW && py <= WB - WW)
            {VGA_R, VGA_G, VGA_B} = 24'hC8E8FF;

         // 3. Goal zones
         if (px >= WL && px < WL + WW && py > GT && py < GB)
            {VGA_R, VGA_G, VGA_B} = 24'hFF8080;
         if (px > WR - WW && px <= WR && py > GT && py < GB)
            {VGA_R, VGA_G, VGA_B} = 24'h8080FF;

         // 4. Centre line
         if ((px == 319 || px == 320) && py >= WT + WW && py <= WB - WW)
            {VGA_R, VGA_G, VGA_B} = 24'hFFFFFF;

         // 5. Centre circle ring
         if (cdist2 >= C_LO && cdist2 <= C_HI)
            {VGA_R, VGA_G, VGA_B} = 24'hFFFFFF;

         // 6. Puck (yellow, radius 10 px)
         if (pdist2 <= PUCK_R2)
            {VGA_R, VGA_G, VGA_B} = 24'hFFFF00;
      end
   end

endmodule


// -------------------------------------------------------
// VGA timing generator — unchanged from lab3 skeleton
// -------------------------------------------------------
module vga_counters(
   input  logic         clk50, reset,
   output logic [10:0]  hcount,
   output logic [9:0]   vcount,
   output logic         VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_n, VGA_SYNC_n);

   parameter HACTIVE      = 11'd 1280,
             HFRONT_PORCH = 11'd 32,
             HSYNC        = 11'd 192,
             HBACK_PORCH  = 11'd 96,
             HTOTAL       = HACTIVE + HFRONT_PORCH + HSYNC + HBACK_PORCH;

   parameter VACTIVE      = 10'd 480,
             VFRONT_PORCH = 10'd 10,
             VSYNC        = 10'd 2,
             VBACK_PORCH  = 10'd 33,
             VTOTAL       = VACTIVE + VFRONT_PORCH + VSYNC + VBACK_PORCH;

   logic endOfLine;

   always_ff @(posedge clk50 or posedge reset)
      if (reset)          hcount <= 0;
      else if (endOfLine) hcount <= 0;
      else                hcount <= hcount + 11'd1;

   assign endOfLine = hcount == HTOTAL - 1;

   logic endOfField;

   always_ff @(posedge clk50 or posedge reset)
      if (reset)          vcount <= 0;
      else if (endOfLine)
         if (endOfField)  vcount <= 0;
         else             vcount <= vcount + 10'd1;

   assign endOfField = vcount == VTOTAL - 1;

   assign VGA_HS = !( (hcount[10:8] == 3'b101) &
                      !(hcount[7:5] == 3'b111));
   assign VGA_VS = !( vcount[9:1] == (VACTIVE + VFRONT_PORCH) / 2);

   assign VGA_SYNC_n  = 1'b0;

   assign VGA_BLANK_n = !( hcount[10] & (hcount[9] | hcount[8]) ) &
                        !( vcount[9] | (vcount[8:5] == 4'b1111) );

   assign VGA_CLK = hcount[0];

endmodule

