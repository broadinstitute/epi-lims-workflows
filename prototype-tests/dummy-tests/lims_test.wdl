version 1.0

# Import sub-workflows
# import "workflows/subwf-atac-single-organism.wdl" as share_atac

workflow LimsTest {
    input {
        String helloWorld
    }

    call myTask {
        input:
            hello_input = helloWorld
            python_environment = "python3"
    }

    task myTask {
        String hello_input
        String version = "hello_world_v1.0.0"
        String python_environment

        command {
            echo ${hello_input}

            python -u<<CODE

            chars = """Hello World!"""
            print(chars)

            import sys
            print(sys.version)

            CODE
        }

        runtime {
            docker: (if python_environment == "python3" then "python:3.6" else "python:2.7") + "-slim"
        }
    }
}