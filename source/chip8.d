// http://www.multigesture.net/articles/how-to-write-an-emulator-chip-8-interpreter/
// https://massung.github.io/CHIP-8/
// https://github.com/dmatlack/chip8/
import std.stdio;
import std.file: read;
import std.random;
import std.string : fromStringz;

import bindbc.sdl;
import bindbc.sdl.image;

const int WIDTH = 64;
const int HEIGHT = 32;

ubyte[80] chip8_fontset = [
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
];

struct Chip8 {
    ushort opcode = 0;
    ushort I = 0;
    ushort pc = 0x200;

    ubyte[4096] memory = [0];

    // Stack
    ushort[16] stack;
    ushort sp = 0;
    // Registers
    ubyte[16] v;

    // Timers
    ubyte delayTimer = 0;
    ubyte soundTimer = 0;

    // Video buffer.
    ubyte[WIDTH*HEIGHT] gfx = [0];

    this(ubyte[] memory) {
        for (auto i = 0; i < memory.length; ++i) {
            writefln("Storing in memory %X data %X", i, memory[i]);
            this.memory[0x200 + i] = memory[i];
        }
    }

    ushort nextOpcode() {
        ubyte first = this.memory[this.pc];
        ubyte second = this.memory[this.pc+1];
        // Big endian
        this.opcode = first << 8 | second;
        this.pc += 2;
        return this.opcode;
    }

    void callSubroutine(ushort subroutine) {
        this.stack[this.sp] = this.pc;
        this.sp++;
        this.pc = subroutine;
    }

    void skipNextInstruction() {
        this.pc += 2;
    }

    ubyte getRandom() {
        return uniform!ubyte();
    }

    ubyte key() {
        // Represents a keypres
        return 0;
    }

    ubyte waitKey() {
        return 0;
    }
}

bool overflows(T)(T x, T y) {
    return x + y < x;
}

bool borrows(ubyte x, ubyte y) {
    return y < x;
}

struct SDLWrapper {
    SDL_Window *appWindow;
    SDL_Renderer *renderer;
};

SDLWrapper *initSDL() {
    const SDLSupport ret = loadSDL();
    if(ret != sdlSupport) {
      writeln("Error loading SDL dll");
      return null;
    }
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        writeln("SDL_Init: ", fromStringz(SDL_GetError()));
    }

    writeln("Creating window");
    SDL_Window* appWin = SDL_CreateWindow(
        "Example #1",
        100,
        100,
        WIDTH,
        HEIGHT,
        SDL_WINDOW_OPENGL
    );
    if (appWin is null) {
        writefln("SDL_CreateWindow: ", SDL_GetError());
        return null;
    }
    scope(exit) {

    }
    writeln("Creating renderer");
    //Create and init the renderer
    SDL_Renderer* ren = SDL_CreateRenderer(appWin, -1, SDL_RENDERER_ACCELERATED);
    if( ren is null) {
        writefln("SDL_CreateRenderer: ", fromStringz(SDL_GetError()));
        return null;
    }

    return new SDLWrapper(appWin, ren);
}

int main() {
    ubyte[] buf = cast(ubyte[])read("./random.ch8");
    writeln(buf);
    Chip8 chip = Chip8(buf);
    SDLWrapper *sdl = initSDL();
    bool running = true;


    while(running) {
        writefln("Running? %s", running? "Yes" : "No");

        chip.nextOpcode();
        auto opcode = chip.opcode;

        if ((opcode & 0xFFF0) == 0x0010) {
            int exitCode = opcode & 0x000F;
            writefln("EXIT %X", exitCode);
            return exitCode;
        } else if (opcode == 0x00E0) {
            writeln("CLS");
        } else if (opcode == 0x00EE) {
            writeln("RET");
            if (chip.sp == 0) {
                writeln("No previous pointer on stack pointer");
                return 2;
            }
            chip.sp--;
            chip.pc = chip.stack[chip.sp];
        } else if ((opcode & 0xF000) == 0x1000) {
            ushort where = opcode & 0x0FFF;
            writefln("JP %X", where);
            chip.pc = where;
        } else if ((opcode & 0xF000) == 0x2000) {
            ushort subroutineMem = opcode & 0x0FFF;
            writefln("CALL %X", subroutineMem);
            chip.callSubroutine(subroutineMem);

        } else if ((opcode & 0xF000) == 0x3000) {
            // Skip equals
            ubyte mem = opcode & 0x00FF;
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("SE V%X, %X", x, mem);

            if (chip.v[x] == chip.memory[mem]) {
                chip.skipNextInstruction();
            }
        } else if ((opcode & 0xF000) == 0x4000) {
            // Skip not equals
            ubyte mem = opcode & 0x00FF;
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("SNE V%X, %X", x, mem);

            if (chip.v[x] != chip.memory[mem]) {
                chip.skipNextInstruction();
            }
        } else if ((opcode & 0xF00F) == 0x5000) {
            // Skip equals
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("SE V%X, V%X", x, y);

            if (chip.v[x] == chip.v[y]) {
                chip.skipNextInstruction();
            }
        } else if ((opcode & 0xF000) == 0x6000) {
            ubyte mem = opcode & 0x00FF;
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD V%X, %X", x, mem);
            chip.v[x] = chip.memory[mem];
        } else if ((opcode & 0xF000) == 0x7000) {
            // Carry flag not setted
            ubyte mem = opcode & 0x00FF;
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("ADD V%X, %X", x, mem);
            chip.v[x] += chip.memory[mem];

            // ============================================== 8XXX ================
        } else if ((opcode & 0xF00F) == 0x8000) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("LD V%X, V%X", x, y);
            chip.v[x] = chip.v[y];
        } else if ((opcode & 0xF00F) == 0x8001) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("OR V%X, V%X", x, y);
            chip.v[x] |= chip.v[y];
        } else if ((opcode & 0xF00F) == 0x8002) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("AND V%X, V%X", x, y);
            chip.v[x] &= chip.v[y];
        } else if ((opcode & 0xF00F) == 0x8003) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("XOR V%X, V%X", x, y);
            chip.v[x] ^= chip.v[y];
        } else if ((opcode & 0xF00F) == 0x8004) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("ADD V%X, V%X", x, y);
            if (chip.v[x] + chip.v[y] < chip.v[x]) {
                chip.v[0xF] = 1;
            }
            chip.v[x] += chip.v[y];
        } else if ((opcode & 0xF00F) == 0x8005) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("SUB V%X, V%X", x, y);
            if (borrows(chip.v[x], chip.v[y])) {
                chip.v[0xF] = 1;
            }
            chip.v[x] -= chip.v[y];
        } else if ((opcode & 0xF00F) == 0x8006) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("SHR V%X, V%X", x, y);
            chip.v[0xF] = 0x000F & chip.v[x];
            chip.v[x] >>= 1;
        } else if ((opcode & 0xF00F) == 0x8007) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("SUBN V%X, V%X", x, y);
            if (borrows(chip.v[y], chip.v[x])) {
                chip.v[0xF] = 1;
            }
            chip.v[x] = cast(ubyte)(chip.v[y] - chip.v[x]);
        } else if ((opcode & 0xF00F) == 0x800E) {
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("SHL V%X, V%X", x, y);
            chip.v[0xF] = 0x000F & chip.v[x];
            chip.v[x] <<= 1;
            // ============================================= 8XXX end =============

            // ============================================= 9XXX start ===========
        } else if ((opcode & 0xF00F) == 0x9000) {
            // SNE Vx, Vy
            ubyte x = (opcode & 0x00F0) >> 4;
            ubyte y = (opcode & 0x0F00) >> 8;
            writefln("SNE V%X, V%X", x, y);

            if (chip.v[x] != chip.v[y]) {
                chip.skipNextInstruction();
            }
        } else if ((opcode & 0xF00F) == 0x9001) {
            version (CHIP8_EXTENDED) {
                // MUL Vx, Vy
                ubyte x = (opcode & 0x00F0) >> 4;
                ubyte y = (opcode & 0x0F00) >> 8;
                writefln("MUL V%X, V%X", x, y);
                chip.v[0xF] = chip.v[x];
            }
        } else if ((opcode & 0xF00F) == 0x9002) {
            version (CHIP8_EXTENDED) {
            }
        } else if ((opcode & 0xF00F) == 0x9003) {
            version (CHIP8_EXTENDED) {
            }
            // ============================================= 9XXX end ===========

            // ============================================= AXXX end ===========
        } else if ((opcode & 0xF000) == 0xA000) {
            ushort loadI = opcode & 0x0FFF;
            writefln("LD I, %X", loadI);
            chip.I = loadI;

            // ============================================= BXXX end ===========
        } else if ((opcode & 0xF000) == 0xB000) {
            // JP V0, NNN
            ushort where = opcode & 0x0FFF;
            writefln("JP V0, %X", where);
            chip.pc =  cast(ushort) (where + chip.v[0]);

            // ==================================================== CXNN ========
        } else if ((opcode & 0xF000) == 0xC000) {
            ubyte mem = opcode & 0x00FF;
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("RND V%X, %X", x, mem);

            // Vx=rand()&NN
            chip.v[x] = chip.getRandom() & chip.memory[mem];

            // ==================================================== DXYN ==========
        } else if ((opcode & 0xF000) == 0xD000) {
            // draw(Vx, Vy, N)
            // Draws a sprite at coordinate (VX, VY)
            // that has a width of 8 pixels and a height of N
            // pixels. Each row of 8 pixels is read as bit-coded
            // starting from memory location I; I value doesn’t change
            // after the execution of this instruction. As described
            // above, VF is set to 1 if any screen pixels are flipped
            // from set to unset when the sprite is drawn, and to 0 if
            // that doesn’t happen

            // Draw 8xN sprite at I to VX, VY; VF = 1 if collision else 0
            ubyte height = opcode & 0x000F;
            ubyte y = (opcode & 0x00F0) >> 4;
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("DRW V%X, V%X, %X", x, y, height);


            // =================================================== EXXX ===========
        } else if ((opcode & 0xF0FF) == 0xE09E) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("SKP V%X", x);

            if (chip.key() == chip.v[x]) {
                chip.skipNextInstruction();
            }
        } else if ((opcode & 0xF0FF) == 0xE0A1) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("SKPN V%X", x);

            if (chip.key() != chip.v[x]) {
                chip.skipNextInstruction();
            }

            // ================================================== FXNN ===========
        } else if ((opcode & 0xF0FF) == 0xF007) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD V%X, DT", x);
            chip.v[x] = chip.delayTimer;
        } else if ((opcode & 0xF0FF) == 0xF00A) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD V%X, K", x);
            // Block til keypress and store on Vx
            chip.v[x] = chip.waitKey();
        } else if ((opcode & 0xF0FF) == 0xF015) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD K, V%X", x);
            chip.delayTimer = chip.v[x];
        } else if ((opcode & 0xF0FF) == 0xF018) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD ST, V%X", x);
            chip.soundTimer = chip.v[x];
        } else if ((opcode & 0xF0FF) == 0xF01E) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("ADD I, V%X", x);

            if(overflows(chip.I, cast(ushort) chip.v[x]) || (chip.I + chip.v[x]) > 0x0FFF) {
                chip.v[0xF] = 1;
            }
            chip.I += chip.v[x];
        } else if ((opcode & 0xF0FF) == 0xF029) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD F, V%X", x);
            //font/sprite load
        } else if ((opcode & 0xF0FF) == 0xF033) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("BCD V%X", x);
        } else if ((opcode & 0xF0FF) == 0xF055) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD [I], V%X", x);
            // reg_dump
        } else if ((opcode & 0xF0FF) == 0xF065) {
            ubyte x = (opcode & 0x0F00) >> 8;
            writefln("LD V%X, [I]", x);
            // reg_load

        } else {
            writefln("Unknown opcode %X", opcode);
            return 1;
        }

        // Set size of renderer to the same as window
        SDL_RenderSetLogicalSize( sdl.renderer, 800, 600 );

        // Set color of renderer to red
        SDL_SetRenderDrawColor( sdl.renderer, 0, 0, 0, 255 );

        // Clear the window and make it all red
        SDL_RenderClear( sdl.renderer );

        // Render the changes above ( which up until now had just happened behind the scenes )
        SDL_RenderPresent( sdl.renderer);

        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                break;
            }

            if (event.type == SDL_KEYDOWN) {
                writeln("Setting running to false");
                running = false;
                // Close and destroy the window
                if (sdl.appWindow !is null) {
                    SDL_DestroyWindow(sdl.appWindow);
                }
                // Close and destroy the renderer
                if (sdl.renderer !is null) {
                    SDL_DestroyRenderer(sdl.renderer);
                }
                SDL_Quit();
                break;
            }
        }
        SDL_Delay(1000);
    }
    return 0;
}
