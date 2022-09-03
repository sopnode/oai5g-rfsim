# run the script with various combinations of options
# and produce an svg for visual inspection
function store-svg() {
    local name=test-logic--"$1"; shift
    python -u ./demo-oai.py --devel -n -v "$@"
    rm demo-oai-graph.dot
    mv demo-oai-graph.svg $name.svg
    echo "==============================" $name from options "$@"
}

store-svg "noopt"
store-svg "load" -l
store-svg "noauto" -a
store-svg "load-noauto" -l -a
store-svg "start" --start
store-svg "stop" --stop
store-svg "cleanup" --cleanup
