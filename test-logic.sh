# run the script with various combinations of options
# and produce an svg for visual inspection
function store-svg() {
    local name=test-logic--"$1"; shift
    python -u ./demo-oai.py --devel -n -v "$@"
    rm demo-oai-graph.dot
    mv demo-oai-graph.svg $name.svg
    echo "==============================" $name from options "$@"
}

function tests-basic() {
    store-svg "noopt"
    store-svg "noopt-nok8reset" -k
    store-svg "load" -l
    store-svg "noauto" -a
    store-svg "load-noauto" -l -a
    store-svg "start" --start
    store-svg "stop" --stop
    store-svg "cleanup" --cleanup
}

# with quectel selected
function tests-quectel() {
    store-svg "quectel1-load" -l -Q 9
    store-svg "quectel2-load" -l -Q 9 -Q 18
    store-svg "quectel1" -Q 9
    store-svg "quectel2" -Q 9 -Q 18
    store-svg "quectel1-cleanup" -Q 9 --cleanup
}

tests-basic
tests-quectel