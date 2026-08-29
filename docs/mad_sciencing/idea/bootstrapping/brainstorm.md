# brainstorm mad science:
Please harshly scrutinies my technology stack. I am going to communicate to many ideas. I need those ideas trimmed down and refined over iterations of  scrutiny. And careful analysis. Iteration is how everything learns right!?

This Is Project **grimoire**. Our tooling repo designed for the future!

We want to use jupyter notebook kernels (probably as a fork???), local AI agents, small LLM's or another architecture. We want to design the future of computer programming interfaces fo the future,Combining new technology and AI to improve everyday peoples ability to create new things. We want to be able to run cool custom jupyter notebook kernels on desktop and phones that let people build and create video games, simulations, and math research, sciences research, computer programming, embedded development, IOT, machine learning, note taking and journaling and project planning. So we will need to design it in a very smart and modular way. We can take inspiration for mixture of experts (MOE) design here. We will use the kernels as our AI model sandbox. And our interface into the real world via kernel interfaces. So a kernel could for example:
- be specialized for game dev on desktop and android.
- be used to develop remotely with a LoRa radio or wifi esp32. from my phone.
- remote REPL python execution on embedded arduino.
-arduino development tools.

The Jupyter Notebook Kernel Interfaces will keep use secure and safe.

Might need a new name for the Kernel interface.

# Human User Interface
The human user interface will be a fork of Jupyter Notebook that we will call "Grimoire" it will be designed to sand box AI and code and to encourage a notes and planning first approach when using AI. We will introduce new cells to the ones that already exist in Jupyter. And add interfaces to tools that allow developer to remotely develop from there phone or laptop on game's, IOT, embedded system projects, 3D printing and modeling projects ect. All through expanding Jupyter Notebook and leveraging python, markdown, and smart Human AI cooperative learning environments via notetaking and Jupyter Notebook.

# Organization:
I have preemptively organized things: 
- **@docs/mad_sciencing/idea:** is where I will be storing all of my project ideas. And plan for how to implement them into grimoire. Most of these will probably be via these jupyter notebook kernels interfaces. 
- **@docs/pdf/hardware/:** is a collection of pdf files that relate to embedded hardware I own.
- **docs/cheatsheets:** Cheat Sheets for humans and AI quick reference.
- **docs/mad_sciencing/questions/:** My curiosity and questions I want to research.
- **docs/mad_sciencing/research/:** Resources for research topic including links.

# Requirements:
1. Must include a side task of building merlin! our own custom AI agent designed to work in grimoire. Possible architectures include:
    a. Bonsai Ternary Neural Networks.
    b. RWKV
    c. Mamba SSM
    d. Real Time Learning
    e. Reservoir computing
    f. Integration with jupyter notebook code and markdown blocks. Add Prompts code block to jyupter notebook. And a diagramming block using mermaid or draw.io.

# new jupyter notebook cells
1. Some sort of natural integration with mermaid or draw.io or another drawing stack that we can use to show both humans and ai diagrams.


# technology dependencies  we could steal from or fork???:
1. python
    a.  https://micropython.org/ and https://github.com/micropython/micropython (micropython)
2. C
    a. https://github.com/tinycc/tinycc (inyCC)
    b. https://documentation.espressif.com/esp32-s3-wroom-1_wroom-1u_datasheet_en.pdf (esp32)
    
3. C++
4.  Jupyter Notebooks Fork
    a. https://github.com/jupyter
5. (Merlin Local AI Possible options) Bonsai Ternary Neural Networks (TNN)
    a. https://github.com/cool-japan/oxibonsai
    b. https://github.com/TripleBites/bonsai_llama_python.git (my own repo from a while back)
    c. https://github.com/TripleBites/bonsai_llama_cpp.git (my own repo from a while back)
    d. https://github.com/PrismML-Eng
6. (Merlin Local AI Possible options) qwen coder 2.5 coder 7b
7. Reticulum Network Stack
    a. https://github.com/markqvist/reticulum
    b. https://reticulum.network/manual/whatis.html
    - Let's build a network of devices capable of plugging into the grimoire developer tool that we are building. I want to be able to create and experiment with hive mind intelligence, distributed systems, and mapping out the real world with IOT for our system (great argument for raw C)
8. Rust???
    - I don't like writing rust code. I kind of want to stick with C / Python for this technology stack. if I can do it without security concerns. But rust's memory safety is a big deal.
    - Maybe we just allow for easy access to rust and embassy for via a programming cell in the user interface to the device via our kernels.

# Targets Device
1. esp32 (Kernel Interface)
2. arduino (Kernel Interface)
3. raspberry pi
4. Remote SSH target raspberry pi zero (Kernel Interface)
5. android termux day one using Jupyter Notebooks web interface.
6. windows 11
7. wsl2 ubuntu 20.04
8. wsl2 ubuntu 24.04
9. Linux
10. Remote SSH target i.MX 6 running Yocto Linux (Kernel Interface)


# 5andbox
We want to use use our new Jupyter Notebook kernel interface as our sandboxing tool output to the world. We want them to be easy to configure the permissions. I should be able to run it safely at my work on very secure and sandboxed credit card payment industry. Where we need absolute security and ability to lock down an environment.

## Questions:
1. **Licensing???:** What does are licensing structure look like with this technology stack.
2. **sympy vs pysys:** I want a good symbolic regression algorithms library
3. **Security:** C vs Rust memory safety bugs and security exploits. Python security. LoRa Radio IOT. Jupyter Notebook fork integration
4. **UV on android termux?:** or should I use normal pip sometimes? I want a secure and simple, single toolchain for this repo. But I had heard that android termux had some issues with there uv versions and some libraries I may want for machine learning and cross platform capabilities.

# Bootstrapping Plans:
1. Brainstorm
2. Interview me. Ask me how clarifying questions and scrutinize the plan. Help me iterate and refine the plan so we can co create the ultimate AI + human powered creativity development tool. 
3. Come up with full plan and get sign the go ahead.
4. Brainstorm Iteration
5. Brainstorm Iteration
6. Brainstorm Iteration
7. Brainstorm Iteration
8. Setup tooling for targets devices. Including startup python scripts to get them running and installed quickly on all target platforms. Any namespace syntax change needed for forking.
9. TBD
