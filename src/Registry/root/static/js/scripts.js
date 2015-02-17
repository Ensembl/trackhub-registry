/* Slider */

$(window).load(function() {
 $('#main-slider').flexslider({
     animation: "slide",
     useCSS: false,
     pauseOnHover: true
 });
});

/* FancyBox  */

$(document).ready(function() {
 $('.fancybox').fancybox();
});

/* Validazione form */

$(document).ready(function(){
 
 $('#contatti-form').validate(
 {
  rules: {
    inputNome: {
      minlength: 2,
      required: true
    },
    inputEmail: {
      required: true,
      email: true
    },
    
    textMessaggio: {
      minlength: 2,
      required: true
    }
  },
  highlight: function(element) {
				$(element).closest('.form-group').removeClass('has-success').addClass('has-error');
			},
			success: function(element) {
				element
				.text('OK!').addClass('text-success')
				.closest('.form-group').removeClass('has-error').addClass('has-success');
			}
	  });
}); 

