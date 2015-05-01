require.config({
    baseUrl: '/static',
	catchError: true,
    paths: {
        jquery: 'bower_components/jquery/jquery',
        d3: 'bower_components/d3/d3.min',
        insert_size_lib: 'bower_components/bcviz/src/qcjson/insertSizeHistogram',
        adapter_lib: 'bower_components/bcviz/src/qcjson/adapter',
        mismatch_lib: 'bower_components/bcviz/src/qcjson/mismatch',
    },
    shim: {
        d3: {
            //makes d3 available automatically for all modules
            exports: 'd3'
        }
    }
});

require.onError = function (err) {
    window.console && console.log(err.requireType);
    window.console && console.log('modules: ' + err.requireModules);
    throw err;
};

function _getTitle(prefix, d) {
    var t = prefix;
    if (d.id_run) { t = t + 'run ' + d.id_run; }
    if (d.position) { t = t + ', lane ' + d.position; }
    if (d.tag_index) { t = t + ', tag ' + d.tag_index; }
    return t;
}


require(['scripts/manual_qc','scripts/collapse', 'insert_size_lib', 'adapter_lib', 'mismatch_lib'], 
function( manual_qc,  collapse, insert_size, adapter, mismatch) {

	collapse.init();
	
	var NPG = NPG || {};
	NPG.QC = NPG.QC || {};
	
	var RunMQCControl = (function () {
	  function RunMQCControl(run_id) {
	    this.run_id = run_id;
	  }
	  
	  RunMQCControl.prototype.initQC = function (mqc_run_data) {
	    if(typeof(mqc_run_data) != undefined
	        && mqc_run_data.taken_by == mqc_run_data.current_user /* Session & qc users are the same */
	        && mqc_run_data.has_manual_qc_role == 1 /* Returns '' if not */
	        && (mqc_run_data.current_status_description == 'qc in progress' 
	          || mqc_run_data.current_status_description == 'qc on hold')) {
	      getQcState();
	    } else {
	      $('.lane_mqc_working').empty(); //There is no mqc so I just remove the working image.
	    }
	  };
	  
	  return RunMQCControl;
	}) ();
	NPG.QC.RunMQCControl = RunMQCControl;
	
	var RunTitleParser = (function () {
	  function RunTitleParser() {
	    this.reId = /^Results for run ([0-9]+)/;
	  }
	  
	  RunTitleParser.prototype.parse = function (element) {
	    var match = this.reId.exec(element);
	    return match[1];
	  };
	  
	  return RunTitleParser;
	}) ();
	NPG.QC.RunTitleParser = RunTitleParser;
	
	//Getting the run_id from the title of the page.
	var run_id = new NPG.QC.RunTitleParser().parse($(document).find("title").text());
	//If the run_id is there //TODO validate number
	if(typeof(run_id) != undefined) {
  	var jqxhr = $.ajax({
  	  url: "/mqc/mqc_runs/" + run_id,
  	  cache: false
  	}).done(function() {
  	  window.console && console.log( "success" );
  	  var control = new NPG.QC.RunMQCControl(run_id);
  	  control.initQC(jqxhr.responseJSON);
  	}).fail(function() {
  	  window.console && console.log( "error" );
  	  //TODO deal with 401 and 500 in different way
  	}).always(function() {
  	  window.console && console.log( "complete" );
  	});
	}
	
	jQuery('.bcviz_insert_size').each(function(i) { 
        d = jQuery(this).data('check');
        w = jQuery(this).data('width') || 650;
        h = jQuery(this).data('height') || 300;
        t = jQuery(this).data('title') || _getTitle('Insert Sizes : ',d);
        chart = insert_size.drawChart({'data': d, 'width': w, 'height': h, 'title': t}); 
        if (chart != null) {
            if (chart.svg != null) {
        div = document.createElement("div");
        jQuery(div).append(function() { return chart.svg.node(); } );
        jQuery(div).addClass('chart');
        jQuery(this).append(div);
            }
        }
    });
	
        jQuery('.bcviz_adapter').each(function(i) { 
        d = jQuery(this).data('check');
        h = jQuery(this).data('height') || 200;
        t = jQuery(this).data('title') || _getTitle('Adapter Start Count : ', d);

		// override width to ensure two graphs can fit side by side
		w = jQuery(this).parent().width() / 2 - 40;
		chart = adapter.drawChart({'data': d, 'width': w, 'height': h, 'title': t}); 
        fwd_div = document.createElement("div");
        if (chart != null && chart.svg_fwd != null) { jQuery(fwd_div).append( function() { return chart.svg_fwd.node(); } ); }
        jQuery(fwd_div).addClass('chart_left');
        rev_div = document.createElement("div");
        if (chart != null && chart.svg_rev != null) { jQuery(rev_div).append( function() { return chart.svg_rev.node(); } ); }
        jQuery(rev_div).addClass('chart_right');
        jQuery(this).append(fwd_div,rev_div);
	});

	jQuery('.bcviz_mismatch').each(function(i) { 
        d = jQuery(this).data('check');
        h = jQuery(this).data('height');
        t = jQuery(this).data('title') || _getTitle('Mismatch : ', d);

		// override width to ensure two graphs can fit side by side
		w = jQuery(this).parent().width() / 2 - 90;
		chart = mismatch.drawChart({'data': d, 'width': w, 'height': h, 'title': t}); 
        fwd_div = document.createElement("div");
        if (chart != null && chart.svg_fwd != null) { jQuery(fwd_div).append( function() { return chart.svg_fwd.node(); } ); }
        jQuery(fwd_div).addClass('chart_left');

        rev_div = document.createElement("div");
        if (chart != null && chart.svg_rev != null) { jQuery(rev_div).append( function() { return chart.svg_rev.node(); } ); }
        jQuery(rev_div).addClass('chart_right');

        leg_div = document.createElement("div");
        if (chart != null && chart.svg_legend != null) { jQuery(leg_div).append( function() { return chart.svg_legend.node(); } ); }
        jQuery(leg_div).addClass('chart_legend');

        jQuery(this).append(fwd_div,rev_div,leg_div);
	});

});
