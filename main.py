import sys
import app

if __name__ == "__main__":
    debug = "--debug" in sys.argv
    app.main(debug=debug)
