module r4_hdmi_rgb(input wire [15:0] rgb,input wire de,hs,vs,
 output wire [23:0] hdmi_d,output wire hdmi_de,hdmi_hs,hdmi_vs);
 assign hdmi_d={{rgb[4:0],rgb[4:2]},{rgb[10:5],rgb[10:9]},{rgb[15:11],rgb[15:13]}};
 assign hdmi_de=de;assign hdmi_hs=hs;assign hdmi_vs=vs;
endmodule
