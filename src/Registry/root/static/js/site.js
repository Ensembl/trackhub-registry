jQuery.support.placeholder = (function(){
  var i = document.createElement('input');
  return 'placeholder' in i;
})();

if (!jQuery.support.placeholder) {
  $('[placeholder]').focus(function() {
    var input = $(this);
    if (input.val() == input.attr('placeholder')) {
      input.val('');
    }
  }).blur(function() {
    var input = $(this);
    if (input.val() == '') {
      input.val(input.attr('placeholder'));
    }
  }).blur().parents('form').submit(function() {
    $(this).find('[placeholder]').each(function() {
      var input = $(this);
      if (input.val() == input.attr('placeholder')) {
        input.val('');
      }
    })
  });
}

$(document).ready( function() {
    $('.dropdown-toggle').dropdown();
    $('[data-toggle="tooltip"]').tooltip(); // initialize all tooltips on a page
    $('[data-toggle="popover"]').tooltip(); // initialize all popovers on a page
});

// Change the right-chevron to down-chevron when people click to show filters
$('.collapse').on('show.bs.collapse', function () {
  var i = $(this).parent('.panel').find('i');
  i.attr('class', 'glyphicon glyphicon-chevron-down');    
});

// Change the down-chevron to right-chevron when people click to hide filters
$('.collapse').on('hide.bs.collapse', function () {
  var i = $(this).parent('.panel').find('i');
  i.attr('class', 'glyphicon glyphicon-chevron-right');    
});

$('ul.dropdown-menu [data-toggle=dropdown]').on('click', function(event) {
    // Avoid following the href location when clicking
    event.preventDefault();
    // Avoid having the menu to close when clicking
    event.stopPropagation();
    // If a menu is already open we close it
    //$('ul.dropdown-menu [data-toggle=dropdown]').parent().removeClass('open');
    // opening the one you clicked on
    $(this).parent().addClass('open');
    
    var menu = $(this).parent().find("ul");
    var menupos = menu.offset();
    
    if((menupos.left + menu.width()) + 30 > $(window).width()) {
      var newpos = - menu.width();
    } else {
      var newpos = $(this).parent().width();
    }
    menu.css({ left:newpos });
});