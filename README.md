# AXI4-Lite Master–Slave System 


This project started out as a personal attempt to really “get” the AXI4-Lite protocol.  
Not by reading PDFs, not by poking at existing IP, but by actually *building* the master, the slave, the wiring between them, and a testbench that hits every corner of the protocol.

If you're someone who wants a small, clean, and fully working AXI example you can study or extend, this repo should feel like home.

---

##  Why AXI4-Lite?

AXI is everywhere — Zynq, ARM SoCs, Vivado IP Integrator… it’s basically the plumbing of modern hardware.  
But AXI4-Lite is the friendlier cousin in the AXI family:

- No bursts  
- Simple, 32-bit data  
- Perfect for memory-mapped registers  

It keeps the important ideas (VALID/READY, five channels, independent read/write paths) without burying you in complexity.

The reference document I used while building all of this breaks AXI4-Lite down into its channels, its timing, and the handshake rules :contentReference[oaicite:0]{index=0}. This project turns that theory into something you can actually simulate and see.

---

##  What’s Inside?

This repo contains four pieces that work together:

### **1. AXI4-Lite Slave**
A simple 16-register memory map.  
Handles:
- byte-enable (WSTRB)
- address decoding
- valid error responses (OKAY / SLVERR)
- independent write and read paths  

The behavior matches what the AXI reference calls out:  
both AW and W handshakes must complete before the slave may issue a write response (see the write timing diagram in the reference, page 5–6) :contentReference[oaicite:1]{index=1}.

### **2. AXI4-Lite Master**
Implements two tiny state machines:
- Write: IDLE → SEND → WAIT → DONE  
- Read: IDLE → SEND → WAIT → DONE  

Unlike most abstracted AXI masters, this one exposes the protocol exactly the way the waveforms describe it (reference page 3–5) :contentReference[oaicite:2]{index=2}.

### **3. System Wrapper**
Just wires the master and slave together — no magic.  
Think of it as a tiny SoC: CPU → AXI-Lite → Peripheral Registers.

### **4. Full Testbench**
This is where everything comes alive. The testbench drives:

- basic write/read  
- sequential writes  
- partial writes (WSTRB tests)  
- readback verification  
- invalid address detection  
- pattern writes across all registers  
- alternating write/read loops  
- random stress test  

Every step prints PASS/FAIL with clear messages, and the waveform makes it trivial to match signals to the logic.

---

## 📐 Architecture Diagram

Below is where the main block diagram goes (master, slave, channels):

<img width="587" height="246" alt="image" src="https://github.com/user-attachments/assets/d2681b7e-2b49-455c-ad06-be98bdb87b81" />

Figure 1. AXI4 Read Transaction.

<img width="587" height="366" alt="image" src="https://github.com/user-attachments/assets/7017a126-acee-4ee3-8146-42ee4cecae8e" />

Figure 2. AXI4 Write Transaction. 



The system is arranged in three layers:

1. **Master**  
   Generates AW, W, AR signals and waits for READY/VALID handshakes.

2. **Slave**  
   Implements a simple register file with address decoding, WSTRB support, and read/write responses.

3. **System Wrapper**  
   Connects the master and slave on all five AXI-Lite channels.

##  A Quick Explanation of AXI4-Lite 

AXI4-Lite uses **five independent channels**:

1. **Write Address (AW)**  
2. **Write Data (W)**  
3. **Write Response (B)**  
4. **Read Address (AR)**  
5. **Read Data (R)**  

Each channel uses the same handshake rule:  

> *A transfer happens only when VALID and READY are both high on the rising clock edge.*

This allows the master and slave to “push back” on each other without dropping data.

---

##  Design Summary

### **Master**
- Write Process:  
  IDLE → SEND ADDR/DATA → WAIT FOR RESPONSE → DONE  
- Read Process:  
  IDLE → SEND ADDR → WAIT FOR DATA → DONE  

### **Slave**
- 16 memory-mapped registers  
- Byte-enable writes (WSTRB handling)  
- Address checking + SLVERR for invalid accesses  

### **Testbench**
Runs automatically through a set of tests:

- Single register write/read  
- Sequential register writes  
- Partial byte writes  
- Register overwrite  
- Back-to-back writes  
- Invalid address checks  
- Pattern tests for all 16 registers  
- Alternating write-read operations  
- Randomized stress test  

Each test prints a clear PASS/FAIL result and produces a final summary.

---

## 🖼 Simulation Outputs

<img width="1365" height="767" alt="Screenshot 2025-12-08 034602" src="https://github.com/user-attachments/assets/0d2befcd-4906-4b63-907f-7901981d2923" />
Figure 3. Fuctional Verification output


## 🧩 RTL / Netlist View

<img width="1362" height="740" alt="Screenshot 2025-12-08 034749" src="https://github.com/user-attachments/assets/b27e5c96-b401-4e35-82ee-e312ead48447" />
Figure 4. RTL / Block view . 

##  Final Thoughts

This project was built to make AXI feel less like a textbook protocol and more like something you can “see” and interact with.

When you simulate it, the timing diagrams from the AXI reference (especially pages 3–6) suddenly stop being abstract — you literally watch them play out on the waveforms.

If you want to extend this setup later, some ideas:

- plug in multiple slaves  
- add a basic interconnect  
- attach the slave to a real datapath (FIFO, ALU, DSP)  
- convert the master to an AXI-Stream generator for fun  

