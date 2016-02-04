/*
 * Module which provides functionality for fetching and rendering QC outcomes
 * from the npg_qc_viewer qcoutcomes JSON service.
 *
 * The function fetchAndProcessQC wraps the logic for fetching the QC outcomes
 * and rendering them in the current page. It also allows to define a callback
 * function to do post processing e.g. prepare the interface for manual QC.
 *
 * The function requires the DOM id for the summary table and the URL for the
 * JSON service as parameters. The callback for postprocessing is optional.
 *
 * Example:
 *
 *   var postRendering = function() {
 *     doSomethingWithRenderedPage();
 *     andMaybeSomethingElse();
 *   }
 *
 *   qc_outcomes_view.fetchAndProcessQC('summary_table_id',
 *                              'qcoutcomes_json_url',
 *                              postRendering);
 *
 */
/* globals $: false, define: false */
'use strict';
define(['jquery'], function () {
  var _classNames = 'qc_outcome_accepted_final qc_outcome_accepted_preliminary qc_outcome_rejected_final qc_outcome_rejected_preliminary qc_outcome_undecided qc_outcome_undecided_final'.split(' ');

  var _classNameForOutcome = function (qcOutcome) {
    var mqcOutcome = typeof qcOutcome !== 'undefined' && typeof qcOutcome.mqc_outcome !== 'undefined' ? qcOutcome.mqc_outcome : '';
    var newClass = 'qc_outcome_' + mqcOutcome.toLowerCase();
    newClass = newClass.replace(/ /g, '_');
    if (_classNames.indexOf(newClass) !== -1) {
      return newClass;
    } else {
      throw 'Unexpected outcome description ' + qcOutcome.mqc_outcome;
    }
  };

  var _processOutcomes = function (outcomes, elementClass) {
    var rpt_keys = Object.keys(outcomes);

    for (var i = 0; i < rpt_keys.length; i++) {
      var rpt_key = rpt_keys[i];
      var qc_outcome = outcomes[rpt_key];
      var new_class = _classNameForOutcome(qc_outcome) ;
      var rptKeyAsSelector;
      if(elementClass === 'lane') {
        rptKeyAsSelector = 'tr[id*="rpt_key:' + rpt_key + '"]';
      } else if (elementClass === 'tag_info') {
        //jQuery can handle ':' as part of a DOM id's but it needs to be escaped as '\\3A '
        rptKeyAsSelector = '#rpt_key\\3A ' + rpt_key.replace(/:/g, '\\3A ');
      } else {
        throw 'Invalid type of rpt key element class ' + elementClass;
      }
      rptKeyAsSelector = rptKeyAsSelector + ' td.' + elementClass;
      $(rptKeyAsSelector).addClass(new_class);
    }
  };

  var _parseRptKeys = function (idTable) {
    var rptKeys = [];
    var idPrefix = 'rpt_key:';
    $('#' + idTable + ' tr').each(function (i, obj) {
      var $obj = $(obj);
      var id = $obj.attr('id');
      if( typeof(id) !== 'undefined' && id !== null && id.lastIndexOf(idPrefix) === 0 ) {
        var rptKey = id.substring(idPrefix.length);
        if( typeof(rptKey) !== 'undefined' && $.inArray(rptKey, rptKeys) === -1 ) {
          rptKeys.push(rptKey);
        }
      }
    });
    return rptKeys;
  };

  var _updateDisplayWithQCOutcomes = function (outcomesData) {
    _processOutcomes(outcomesData.lib, 'tag_info');
    _processOutcomes(outcomesData.seq, 'lane');
  };

  var _buildQuery = function (rptKeys) {
    var data = { };
    for( var i = 0; i < rptKeys.length; i++ ) {
      data[rptKeys[i]] = {};
    }
    return data;
  };

  var _fetchQCOutcomesUpdateView = function (rptKeys, outcomesURL, callOnSuccess) {
    var data = _buildQuery(rptKeys);

    $.ajax({
      url: outcomesURL,
      type: 'POST',
      contentType: 'application/json',
      data: JSON.stringify(data),
      cache: false
    }).error(function(jqXHR, textStatus, errorThrown) {
      $('#ajax_status').append("<li class='failed_mqc'>Error while fetching QC outcomes. " + errorThrown + '</li>');
    }).success(function (data) {
      try {
        _updateDisplayWithQCOutcomes(data);
        if(typeof callOnSuccess === 'function' ) {
          callOnSuccess();
        }
      } catch (er) {
        throw er;
      }
    });
  };

  var fetchAndProcessQC = function (tableID, qcOutcomesURL, callbackAfterUpdateView) {
    try {
      var rptKeys = _parseRptKeys(tableID);
      _fetchQCOutcomesUpdateView(rptKeys, qcOutcomesURL, callbackAfterUpdateView);
    } catch (er) {
      var message;
      if(typeof er === 'string') {
        message = er;
      } else if (typeof er === 'object' && typeof er.message === 'string') {
          message = er.message;
      } else {
        message = '' + er;
      }
      $('#ajax_status').append("<li class='failed_mqc'>" + message + '</li>');
    }
  };

  return {
    _fetchQCOutcomesUpdateView : _fetchQCOutcomesUpdateView,
    _buildQuery: _buildQuery,
    _updateDisplayWithQCOutcomes: _updateDisplayWithQCOutcomes,
    _parseRptKeys: _parseRptKeys,
    fetchAndProcessQC: fetchAndProcessQC,
  };
});
