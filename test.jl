# `export LIBSERIALPORT_DEBUG=` to display debug info (`unset` to clear)

include("libserialport.jl")

"""
Print libserialport version (tested on 0.1.1)
"""
function print_library_version()
    # TODO replace this with wrapped version
    ver = ccall((:sp_get_package_version_string, "libserialport"), Ptr{UInt8}, ())
    println(bytestring(ver))
end

"""
Print a list of currently visible ports, along with some basic info
"""
function list_ports()
    ports = sp_list_ports()
    nports_overestimate = 32

    for port in pointer_to_array(ports, nports_overestimate, false)
        port == C_NULL && return

        println(sp_get_port_name(port))
        println("\tDescription:\t",    sp_get_port_description(port))
        println("\tTransport type:\t", sp_get_port_transport(port))
    end

    sp_free_port_list(ports)
    return
end

"""
Print info found for this port.
Note: port should be open to obtain a valid FD/handle before accessing fields.
"""
function print_port_info(port; show_config::Bool=true)
    println("\nPort name:\t",       sp_get_port_name(port))
    println("Manufacturer:\t",      sp_get_port_usb_manufacturer(port))
    println("Product:\t",           sp_get_port_usb_product(port))
    println("USB serial number:\t", sp_get_port_usb_serial(port))
    println("Bluetooth address:\t", sp_get_port_bluetooth_address(port))
    println("File descriptor:\t",   sp_get_port_handle(port))

    bus, addr = sp_get_port_usb_bus_address(port)
    if bus != -1
        println("USB bus #:\t",   bus)
        println("Address on bus:\t",  addr)
    end

    vid, pid = sp_get_port_usb_vid_pid(port)
    if vid != -1
        println("Vendor ID:\t",   vid)
        println("Product ID:\t",  pid)
    end
    if show_config
        print_port_config(port)
    end
end

function print_port_config(port)
    println("Configuration for ", sp_get_port_name(port), ":")
    config = sp_get_config(port)
    print_config_info(config)
    sp_free_config(config)
end

"""
Print settings currently stored in sp_port_config struct
"""
function print_config_info(config)
    println("\tbaudrate\t", sp_get_config_baudrate(config))
    println("\tbits\t",     sp_get_config_bits(config))
    println("\tparity\t",   sp_get_config_parity(config))
    println("\tstopbits\t", sp_get_config_stopbits(config))
    println("\tRTS\t",      sp_get_config_rts(config))
    println("\tCTS\t",      sp_get_config_cts(config))
    println("\tDTR\t",      sp_get_config_dtr(config))
    println("\tDSR\t",      sp_get_config_dsr(config))
    println("\tXonXoff\t",  sp_get_config_xon_xoff(config))
    println("")
end

"""
Test that we can change some port configuration settings on a copy of the
provided port. Use two approaches to cover the various set and get functions.
The original port configuration should not be modified by these tests!
"""
function test_port_configuration(port)
    # 1. (Direct) use setter functions for the port struct
    test_change_port_copy_method1(port)
    # 2. (Roundabout) get a new sp_port_configuration instance, modify it, then
    # copy its data fields to the port struct.
    test_change_port_copy_method2(port)
end

function test_change_port_copy_method1(port)
    port2 = sp_copy_port(port)
    sp_close(port)
    sp_open(port2, SP_MODE_READ_WRITE)

    # Beware of error that RTS & CTS flow control must be enabled together

    print("\n[TEST1] INITIAL ")
    print_port_config(port2)
    println("[TEST1] changing port configuration settings.")
    sp_set_baudrate(port2, 115200)
    sp_set_bits(port2, 6)
    sp_set_parity(port2, SP_PARITY_EVEN)
    sp_set_stopbits(port2, 2)
    sp_set_rts(port2, SP_RTS_OFF)
    sp_set_cts(port2, SP_CTS_IGNORE)
    sp_set_dtr(port2, SP_DTR_OFF)
    sp_set_dsr(port2, SP_DSR_IGNORE)
    sp_set_xon_xoff(port2, SP_XONXOFF_INOUT)

    print("[TEST1] UPDATED ")
    print_port_config(port2)

    println("[TEST1] closing and deleting copied port")
    sp_close(port2)
    sp_free_port(port2)

    println("[TEST1] reopening original port")
    sp_open(port, SP_MODE_READ_WRITE)

    print("[TEST1] ORIGINAL ")
    print_port_config(port)
end

function test_change_port_copy_method2(port)
    port2 = sp_copy_port(port)
    sp_close(port)
    sp_open(port2, SP_MODE_READ_WRITE)

    # Beware of error that RTS & CTS flow control must be enabled together

    # Either
    # config2 = sp_new_config()
    # Or
    config2 = sp_get_config(port2)

    print("\n[TEST2] INITIAL ")
    print_config_info(config2)

    println("[TEST2] changing configuration settings.")
    sp_set_config_baudrate(config2, 115200)
    sp_set_config_bits(config2, 6)
    sp_set_config_parity(config2, SP_PARITY_EVEN)
    sp_set_config_stopbits(config2, 2)
    sp_set_config_rts(config2, SP_RTS_OFF)
    sp_set_config_cts(config2, SP_CTS_IGNORE)
    sp_set_config_dtr(config2, SP_DTR_OFF)
    sp_set_config_dsr(config2, SP_DSR_IGNORE)
    sp_set_config_xon_xoff(config2, SP_XONXOFF_INOUT)

    sp_set_config(port2, config2)
    sp_free_config(config2)

    print("[TEST2] UPDATED ")
    print_port_config(port2)

    println("[TEST2] closing and deleting copied port")
    sp_close(port2)
    sp_free_port(port2)

    println("[TEST2] reopening original port")
    sp_open(port, SP_MODE_READ_WRITE)

    print("[TEST2] ORIGINAL ")
    print_port_config(port)
end

"""
This example demonstrates serial communication with one port. The default
configuration is 9600-8-N-1, i.e. 9600 bps with 8 data bits, no parity check,
and one stop bit. The baud rate is overridden on the command line with a
second argument. Hardware and software flow control measures are disabled by
default.
"""
function main()

    nargs = length(ARGS)
    if nargs == 0
        println("Usage: test.jl port [baudrate]")
        println("Available ports:")
        list_ports()
        return
    end

    port = sp_get_port_by_name(ARGS[1]) # e.g. "/dev/cu.wchusbserial1410"
    baudrate = nargs >= 2 ? ARGS[2] : 9600

    print_library_version()
    list_ports()

    sp_open(port, SP_MODE_READ_WRITE)

    # test_port_configuration(port)

    sp_set_baudrate(port, parse(Int, baudrate))

    println(sp_blocking_read(port, 128, 3000))
    sp_drain(port)
    sp_flush(port, SP_BUF_BOTH)

    counter = 0
    while counter < 100
        counter += 1
        msg = Array{UInt8}("Message $counter\n")
        # sp_nonblocking_write(port, msg)
        sp_blocking_write(port, msg, 50)

        # Wait up to 100 ms for the output buffer to clear out
        countdown = 100
        while Int(sp_output_waiting(port)) > 0 && countdown > 0
            sleep(0.001)
            countdown -= 1
        end

        # Done writing, now read
        countdown = 100
        while Int(sp_input_waiting(port)) > 0 && countdown > 0
            sleep(0.001)
            countdown -= 1
        end
        # result = sp_nonblocking_read(port, 64)
        result = sp_blocking_read(port, 64, 50)
        if length(result) > 0
            print(result)
        end

        sp_drain(port)
        sp_flush(port, SP_BUF_BOTH)
    end

    println("\nClosing and freeing port. Over and out.")
    sp_close(port)
    sp_free_port(port)
end

main()